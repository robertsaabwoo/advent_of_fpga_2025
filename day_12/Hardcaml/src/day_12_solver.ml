open! Core
open! Hardcaml
open! Signal

(* ========== Configuration & Constants ========== *)

module Constants = struct
  let num_gifts = 6
  let num_orientations = 8
  let shape_height = 4 
  let shape_width_bits = 4 
end

module Config = struct
  type t =
    { max_grid_size : int
    ; max_gifts : int
    }
  let default = { max_grid_size = 16; max_gifts = 12 }
end

(* ========== Shape ROM ========== *)

module Shapes = struct
  let all =
    [| (* Gift 0 *)
       [| [| 0x6; 0x6; 0x7; 0x0 |]; [| 0x6; 0x7; 0x3; 0x0 |]; [| 0x0; 0xe; 0x6; 0x6 |]; [| 0xc; 0xe; 0x6; 0x0 |];
          [| 0x6; 0xc; 0x6; 0x0 |]; [| 0x0; 0x3; 0x6; 0xc |]; [| 0x0; 0x7; 0x6; 0x4 |]; [| 0x8; 0xe; 0x6; 0x0 |] |];
       (* Gift 1 *)
       [| [| 0x3; 0x6; 0x7; 0x0 |]; [| 0x6; 0x7; 0x1; 0x0 |]; [| 0x0; 0xe; 0x6; 0xc |]; [| 0x8; 0xe; 0x6; 0x0 |];
          [| 0xc; 0xe; 0x6; 0x0 |]; [| 0x0; 0xe; 0x6; 0x3 |]; [| 0x0; 0xc; 0x6; 0x8 |]; [| 0x2; 0xe; 0x6; 0x0 |] |];
       (* Gift 2 *)
       [| [| 0x6; 0x7; 0x3; 0x0 |]; [| 0xc; 0x6; 0x6; 0x0 |]; [| 0x0; 0xc; 0xe; 0x6 |]; [| 0x6; 0x6; 0x3; 0x0 |];
          [| 0xc; 0xe; 0x6; 0x0 |]; [| 0x0; 0x6; 0xe; 0x3 |]; [| 0x6; 0x7; 0x3; 0x0 |]; [| 0xc; 0x6; 0x6; 0x0 |] |];
       (* Gift 3 *)
       [| [| 0x6; 0x7; 0x6; 0x0 |]; [| 0x6; 0x7; 0x6; 0x0 |]; [| 0x6; 0x7; 0x6; 0x0 |]; [| 0x6; 0x7; 0x6; 0x0 |];
          [| 0x6; 0xc; 0x6; 0x0 |]; [| 0x6; 0x3; 0x6; 0x0 |]; [| 0x6; 0x3; 0x6; 0x0 |]; [| 0x6; 0xc; 0x6; 0x0 |] |];
       (* Gift 4 *)
       [| [| 0x7; 0x1; 0x7; 0x0 |]; [| 0x6; 0x7; 0x2; 0x0 |]; [| 0x0; 0xe; 0x4; 0xe |]; [| 0x4; 0xe; 0x6; 0x0 |];
          [| 0xe; 0x4; 0xe; 0x0 |]; [| 0x0; 0xe; 0x4; 0xe |]; [| 0x6; 0x7; 0x2; 0x0 |]; [| 0x4; 0xe; 0x6; 0x0 |] |];
       (* Gift 5 *)
       [| [| 0x7; 0x2; 0x7; 0x0 |]; [| 0x4; 0x7; 0x6; 0x0 |]; [| 0x0; 0xe; 0x4; 0xe |]; [| 0x6; 0xe; 0x2; 0x0 |];
          [| 0xe; 0x4; 0xe; 0x0 |]; [| 0x0; 0xe; 0x4; 0xe |]; [| 0x4; 0x7; 0x6; 0x0 |]; [| 0x6; 0xe; 0x2; 0x0 |] |];
    |]

  let get_row ~gift_id ~orient ~row_idx =
    let select_from_array arr idx =
      mux idx (Array.to_list arr |> List.map ~f:(fun x -> Signal.of_int_trunc ~width:4 x))
    in
    let rows_for_gift =
      Array.map all ~f:(fun orientations ->
        let rows_for_orient =
          Array.map orientations ~f:(fun rows -> select_from_array rows row_idx)
        in
        mux orient (Array.to_list rows_for_orient)
      )
    in
    mux gift_id (Array.to_list rows_for_gift)
end

(* ========== Interfaces ========== *)

module I = struct
  type 'a t =
    { clock : 'a
    ; clear : 'a
    ; s_tvalid : 'a 
    ; s_tdata : 'a [@bits 8] 
    ; m_tready : 'a 
    }
  [@@deriving hardcaml]
end

module O = struct
  type 'a t =
    { s_tready : 'a 
    ; m_tvalid : 'a 
    ; m_tlast : 'a 
    ; m_tdata : 'a [@bits 8] 
    }
  [@@deriving hardcaml]
end

module State = struct
  type t =
    | Init_shapes
    | Idle
    | Read_counts 
    | Init_clear_ram 
    | Init_expand 
    | Start_solver 
    | Check_place_addr 
    | Check_place_wait 
    | Check_place_verify 
    | Check_place_write 
    | Next_step 
    | Undo_addr 
    | Undo_wait 
    | Undo_write 
    | Output 
  [@@deriving sexp_of, compare ~localize, enumerate]
end

let create ?(config = Config.default) _scope (i : _ I.t) =
  let open Always in

  (* Width Calculations *)
  let addr_width = Int.ceil_log2 config.max_grid_size in
  let coord_width = 8 in
  let gift_ptr_width = Int.ceil_log2 (config.max_gifts + 1) in
  let mask_width = 16 in

  let spec = Reg_spec.create ~clock:i.clock ~clear:i.clear () in
  let sm = State_machine.create (module State) spec in

  (* ---- Registers: Input / Control ---- *)
  let region_w = Variable.reg spec ~width:coord_width in
  let region_h = Variable.reg spec ~width:coord_width in
  let input_cnt = Variable.reg spec ~width:3 in
  let temp_counts = Array.init Constants.num_gifts ~f:(fun _ -> Variable.reg spec ~width:8) in

  let clear_iter = Variable.reg spec ~width:addr_width in
  let row_iter = Variable.reg spec ~width:3 in
  let total_gifts = Variable.reg spec ~width:gift_ptr_width in

  (* DFS Pointers *)
  let gift_ptr = Variable.reg spec ~width:gift_ptr_width in
  let next_gift_ptr = Variable.reg spec ~width:gift_ptr_width in
  let next_gift_valid = Variable.reg spec ~width:1 in
  let solution_found = Variable.reg spec ~width:1 in
  let solution_valid = Variable.reg spec ~width:1 in

  (* Backtrack State *)
  let undo_idx = Variable.reg spec ~width:gift_ptr_width in
  let undo_row_iter = Variable.reg spec ~width:3 in

  (* ========================================================================= *)
  (* REPLACEMENT: REGISTERS INSTEAD OF RAM *)
  (* ========================================================================= *)

  (* 1. Gift ID Registers *)
  let gift_id_regs = Array.init config.max_gifts ~f:(fun _ -> Variable.reg spec ~width:3) in
  
  (* 2. Stack Registers *)
  let stack_x_regs = Array.init config.max_gifts ~f:(fun _ -> Variable.reg spec ~width:coord_width) in
  let stack_y_regs = Array.init config.max_gifts ~f:(fun _ -> Variable.reg spec ~width:coord_width) in
  let stack_orient_regs = Array.init config.max_gifts ~f:(fun _ -> Variable.reg spec ~width:3) in

  (* Helper to read from register array based on a pointer *)
  let read_reg_array (regs : Variable.t array) (ptr : Signal.t) = 
    let values = List.init (Array.length regs) ~f:(fun idx -> (regs.(idx)).value) in
    Signal.mux ptr values
  in

  (* Write Enable Signals *)
  let stack_write_ptr = Variable.wire ~default:(zero gift_ptr_width) () in
  let stack_wen       = Variable.wire ~default:gnd () in
  
  (* Data to write *)
  let wdata_gid    = Variable.wire ~default:(zero 3) () in
  let wdata_x      = Variable.wire ~default:(zero coord_width) () in
  let wdata_y      = Variable.wire ~default:(zero coord_width) () in
  let wdata_orient = Variable.wire ~default:(zero 3) () in
  
  let gid_wen = Variable.wire ~default:gnd () in

  (* ========================================================================= *)
  (* Logic Helpers *)
  (* ========================================================================= *)

  let use_undo = sm.is Undo_addr |: sm.is Undo_wait |: sm.is Undo_write in
  
  (* Read Active Values *)
  let active_ptr = mux2 use_undo undo_idx.value gift_ptr.value in

  let active_gid    = read_reg_array gift_id_regs active_ptr in
  let current_x     = read_reg_array stack_x_regs active_ptr in
  let current_y     = read_reg_array stack_y_regs active_ptr in
  let current_orient= read_reg_array stack_orient_regs active_ptr in
  
  let active_x = current_x in
  let active_y = current_y in
  let active_orient = current_orient in

  (* Board Memory (Main Grid) *)
  let ram_addr = Variable.wire ~default:(zero addr_width) () in
  let ram_wen = Variable.wire ~default:gnd () in
  let ram_wdata = Variable.wire ~default:(zero mask_width) () in

  let board_mem = Ram.create
    ~size:config.max_grid_size
    ~collision_mode:Read_before_write
    ~write_ports:[| { write_clock = i.clock; write_address = ram_addr.value; write_enable = ram_wen.value; write_data = ram_wdata.value } |]
    ~read_ports:[| { read_clock = i.clock; read_address = ram_addr.value; read_enable = vdd } |]
    ()
  in
  (* PIPELINE REGISTER FOR RAM READ *)
  let ram_rdata_reg = Variable.reg spec ~width:mask_width in
  let ram_rdata = ram_rdata_reg.value in

  (* ---- Mask Calculation ---- *)
  let active_row_iter = mux2 use_undo undo_row_iter.value row_iter.value in
  let target_addr = (active_y +: (uresize active_row_iter ~width:coord_width)) in
  let relative_y = active_row_iter in
  let row_in_shape_bounds = (relative_y <:. Constants.shape_height) &: (target_addr <: region_h.value) in

  let shape_bits = Shapes.get_row
    ~gift_id:active_gid
    ~orient:active_orient
    ~row_idx:(relative_y.:[1,0])
  in

  let raw_mask = mux2 row_in_shape_bounds
    (uresize (zero 12 @: shape_bits) ~width:mask_width)
    (zero mask_width)
  in
  let shifted_mask = log_shift ~f:sll raw_mask ~by:(uresize active_x ~width:(Int.ceil_log2 mask_width)) in

  (* ---- Collision Detection ---- *)
  let region_w_clog = uresize region_w.value ~width:(Int.ceil_log2 (mask_width + 1)) in
  let valid_region_mask = (log_shift ~f:sll (one mask_width) ~by:region_w_clog) -: (one mask_width) in
  let bounds_mask = ~: valid_region_mask in

  let collision =
    ((ram_rdata &: shifted_mask) <>:. 0) |:  
    ((shifted_mask &: bounds_mask) <>:. 0) |: 
    (target_addr >=: region_h.value) 
  in

  let s_tready_comb = sm.is Idle |: sm.is Read_counts in

  compile [
    (* 1. Pipeline Register Assignment *)
    ram_rdata_reg <-- board_mem.(0);

    (* 2. Default Control Signals *)
    ram_wen <-- gnd;
    ram_addr <-- target_addr.:[addr_width-1, 0];
    
    stack_wen <-- gnd;
    gid_wen <-- gnd;
    stack_write_ptr <-- gift_ptr.value; (* Default write to current *)
    
    wdata_gid <-- zero 3;
    wdata_x <-- zero coord_width;
    wdata_y <-- zero coord_width;
    wdata_orient <-- zero 3;

    (* 3. Explicit Register Array Write Logic *)
    proc (
      List.concat (List.init config.max_gifts ~f:(fun k ->
        (* FIX: of_int_trunc here *)
        let is_target = stack_write_ptr.value ==: (of_int_trunc ~width:gift_ptr_width k) in
        [
          (* Stack registers update *)
          if_ (stack_wen.value &: is_target) [
             stack_x_regs.(k)      <-- wdata_x.value;
             stack_y_regs.(k)      <-- wdata_y.value;
             stack_orient_regs.(k) <-- wdata_orient.value;
          ] [];
          
          (* Gift ID update *)
          if_ (gid_wen.value &: is_target) [
             gift_id_regs.(k) <-- wdata_gid.value;
          ] []
        ]
      ))
    );

    (* 4. State Machine *)
    sm.switch [
      Init_shapes, [ sm.set_next Idle ];

      Idle, [
        if_ i.s_tvalid [
          region_w <-- i.s_tdata;
          input_cnt <-- of_int_trunc ~width:3 1;
          sm.set_next Read_counts;
        ] []
      ];

      Read_counts, [
        if_ i.s_tvalid [
          if_ (input_cnt.value ==:. 1) [
            region_h <-- i.s_tdata;
            input_cnt <-- of_int_trunc ~width:3 2;
          ] [
            switch (input_cnt.value -: of_int_trunc ~width:3 2) (List.init 6 ~f:(fun k -> 
              (of_int_trunc ~width:3 k, [ temp_counts.(k) <-- i.s_tdata ])
            ));
          ];
          if_ (input_cnt.value ==:. 1) [] [
            if_ (input_cnt.value ==:. 7) [
              clear_iter <-- zero addr_width;
              sm.set_next Init_clear_ram;
            ] [
              input_cnt <-- input_cnt.value +:. 1;
            ]
          ]
        ] []
      ];

      Init_clear_ram, [
        ram_addr <-- clear_iter.value;
        ram_wdata <-- zero mask_width;
        ram_wen <-- vdd;
        if_ (clear_iter.value ==: of_int_trunc ~width:addr_width 15) [
          input_cnt <-- zero 3;
          total_gifts <-- zero gift_ptr_width;
          sm.set_next Init_expand;
        ] [
          clear_iter <-- clear_iter.value +:. 1;
        ]
      ];

      Init_expand, [
        let count_val = Signal.mux input_cnt.value (Array.to_list (Array.map temp_counts ~f:(fun v -> v.value))) in
        if_ ((count_val <>:. 0) &: (total_gifts.value <: of_int_trunc ~width:gift_ptr_width config.max_gifts)) [
          stack_write_ptr <-- total_gifts.value;
          wdata_gid       <-- input_cnt.value;
          gid_wen         <-- vdd;

          switch input_cnt.value (List.init 6 ~f:(fun k ->
             (of_int_trunc ~width:3 k, [ temp_counts.(k) <-- temp_counts.(k).value -:. 1 ])
          ));
          total_gifts <-- total_gifts.value +:. 1;
        ] [
          if_ (input_cnt.value ==:. 5) [
            sm.set_next Start_solver;
          ] [
            input_cnt <-- input_cnt.value +:. 1;
          ]
        ]
      ];

      Start_solver, [
        gift_ptr <-- zero gift_ptr_width;
        next_gift_ptr <-- of_int_trunc ~width:gift_ptr_width 1;
        next_gift_valid <-- (total_gifts.value >:. 1);
        
        stack_write_ptr <-- zero gift_ptr_width;
        wdata_x         <-- zero coord_width;
        wdata_y         <-- zero coord_width;
        wdata_orient    <-- zero 3;
        stack_wen       <-- vdd;

        row_iter <-- zero 3;
        solution_found <-- gnd;
        solution_valid <-- gnd;
        sm.set_next Check_place_addr;
      ];

      Check_place_addr, [ sm.set_next Check_place_wait ];
      Check_place_wait, [ sm.set_next Check_place_verify ];

      Check_place_verify, [
        if_ collision [ sm.set_next Next_step ] [ sm.set_next Check_place_write ]
      ];

      Check_place_write, [
        if_ (target_addr <: region_h.value) [
           ram_wdata <-- (ram_rdata |: shifted_mask);
           ram_wen <-- vdd;
        ] [];

        if_ (row_iter.value <:. 3) [
          row_iter <-- row_iter.value +:. 1;
          sm.set_next Check_place_addr;
        ] [
          if_ (gift_ptr.value ==: (total_gifts.value -:. 1)) [
            solution_found <-- vdd;
            solution_valid <-- vdd;
            sm.set_next Output;
          ] [
            gift_ptr <-- gift_ptr.value +:. 1;
            next_gift_ptr <-- gift_ptr.value +:. 2;
            next_gift_valid <-- (gift_ptr.value +:. 2 <: total_gifts.value);
            
            stack_write_ptr <-- gift_ptr.value +:. 1;
            wdata_x         <-- zero coord_width;
            wdata_y         <-- zero coord_width;
            wdata_orient    <-- zero 3;
            stack_wen       <-- vdd;
            
            row_iter <-- zero 3;
            sm.set_next Check_place_addr;
          ]
        ]
      ];

      Next_step, [
        if_ (current_orient <:. 7) [
           stack_write_ptr <-- gift_ptr.value;
           wdata_x         <-- current_x;
           wdata_y         <-- current_y;
           wdata_orient    <-- current_orient +:. 1;
           stack_wen       <-- vdd;
           
           row_iter <-- zero 3;
           sm.set_next Check_place_addr;
        ] [
           if_ (current_x <: (region_w.value -:. 1)) [
              stack_write_ptr <-- gift_ptr.value;
              wdata_x         <-- current_x +:. 1;
              wdata_y         <-- current_y;
              wdata_orient    <-- zero 3;
              stack_wen       <-- vdd;

              row_iter <-- zero 3;
              sm.set_next Check_place_addr;
           ] [
              if_ (current_y <: (region_h.value -:. 1)) [
                 stack_write_ptr <-- gift_ptr.value;
                 wdata_x         <-- zero coord_width;
                 wdata_y         <-- current_y +:. 1;
                 wdata_orient    <-- zero 3;
                 stack_wen       <-- vdd;

                 row_iter <-- zero 3;
                 sm.set_next Check_place_addr;
              ] [
                 if_ (gift_ptr.value ==:. 0) [
                    solution_found <-- gnd;
                    solution_valid <-- vdd;
                    sm.set_next Output;
                 ] [
                    undo_idx <-- gift_ptr.value -:. 1;
                    undo_row_iter <-- zero 3;
                    sm.set_next Undo_addr;
                 ]
              ]
           ]
        ]
      ];

      Undo_addr, [ sm.set_next Undo_wait ];
      Undo_wait, [ sm.set_next Undo_write ];

      Undo_write, [
          if_ (target_addr <: region_h.value) [
            ram_wdata <-- (ram_rdata &: (~: shifted_mask));
            ram_wen <-- vdd;
          ] [];

          if_ (undo_row_iter.value <:. 3) [
             undo_row_iter <-- undo_row_iter.value +:. 1;
             sm.set_next Undo_addr;
          ] [
             gift_ptr <-- undo_idx.value;
             row_iter <-- zero 3;
             next_gift_ptr <-- undo_idx.value +:. 1;
             next_gift_valid <-- vdd;
             sm.set_next Next_step;
          ]
      ];

      Output, [
        if_ i.m_tready [ sm.set_next Idle ] []
      ];
    ]
  ];

  { O.
    s_tready = s_tready_comb
  ; m_tvalid = sm.is Output
  ; m_tlast  = sm.is Output
  ; m_tdata  = uresize (solution_found.value &: solution_valid.value) ~width:8
  }
;;

let hierarchical ?(config = Config.default) scope =
  let module Scoped = Hierarchy.In_scope (I) (O) in
  Scoped.hierarchical ~scope ~name:"Day_12_solver" (create ~config)
;;