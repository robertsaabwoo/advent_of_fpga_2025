open! Core
open! Hardcaml

(* Alias Day_12_solver module *)
module Day_12 = Hardcaml_demo_project.Day_12_solver

(* Use shape constants from hardware module *)
let shapes = Day_12.Shapes.all

module Sim = Cyclesim.With_interface (Day_12.I) (Day_12.O)

(* ========== Reference Solver (Software Model) ========== *)

(* Helper to count bits *)
let count_set_bits n =
  let rec aux v acc = if v = 0 then acc else aux (v land (v - 1)) (acc + 1) in
  aux n 0

(* Calculate area of each shape - precomputed at startup *)
let shape_areas =
  Array.map shapes ~f:(fun orientations ->
    let rows = orientations.(0) in
    Array.fold rows ~init:0 ~f:(fun acc r -> acc + count_set_bits r)
  )

(* Recursive DFS Solver with Fast Fail - validates hardware results *)
let solve_reference ~width ~height ~gift_counts =
  let total_gift_area =
    List.foldi gift_counts ~init:0 ~f:(fun idx acc count ->
      acc + (count * shape_areas.(idx))
    )
  in
  let grid_area = width * height in

  if total_gift_area > grid_area then false else
  begin
    let board = Array.create ~len:height 0 in
    let gifts =
      List.concat_mapi gift_counts ~f:(fun id count -> List.init count ~f:(fun _ -> id))
      |> Array.of_list
    in
    let num_gifts = Array.length gifts in

    let fit gift_id orient x y =
      let shape = shapes.(gift_id).(orient) in
      let rec check_rows r =
        if r = 4 then true
        else if shape.(r) = 0 then check_rows (r + 1)
        else (
          let by = y + r in
          if by >= height then false
          else (
            let row_mask = shape.(r) lsl x in
            if (row_mask lsr x) <> shape.(r) then false
            else if (row_mask land (lnot ((1 lsl width) - 1))) <> 0 then false
            else if (board.(by) land row_mask) <> 0 then false
            else check_rows (r + 1)
          )
        )
      in
      check_rows 0
    in

    let toggle_place gift_id orient x y =
      let shape = shapes.(gift_id).(orient) in
      for r = 0 to 3 do
        if y + r < height then
          board.(y + r) <- board.(y + r) lxor (shape.(r) lsl x)
      done
    in

    let rec dfs idx call_limit =
      if idx = num_gifts then true
      else if !call_limit <= 0 then false
      else (
        decr call_limit;
        let gid = gifts.(idx) in
        let rec loop_orient o =
          if o = 8 then false
          else (
            let rec loop_y y =
              if y = height then false
              else (
                let rec loop_x x =
                  if x = width then false
                  else (
                    if fit gid o x y then (
                      toggle_place gid o x y;
                      if dfs (idx + 1) call_limit then true
                      else (toggle_place gid o x y; loop_x (x + 1))
                    ) else loop_x (x + 1)
                  )
                in
                if loop_x 0 then true else loop_y (y + 1)
              )
            in
            if loop_y 0 then true else loop_orient (o + 1)
          )
        in
        loop_orient 0
      )
    in
    dfs 0 (ref 20000)
  end

(* ========== Testbench Driver ========== *)

let%expect_test "day 12 verification" =
  let sim = Sim.create (Day_12.create (Scope.create ())) in
  let inputs = Cyclesim.inputs sim in
  let outputs = Cyclesim.outputs sim in

  let send_word data =
    inputs.s_tvalid := Bits.vdd;
    inputs.s_tdata := Bits.of_int_trunc ~width:8 data;
    
    let cycles_wait = ref 0 in
    let rec wait () =
      (* Check ready signal BEFORE clock edge *)
      let ready = Bits.to_bool !(outputs.s_tready) in
      Cyclesim.cycle sim;
      incr cycles_wait;
      
      if not ready then (
        if !cycles_wait > 50 then failwith "Stuck waiting for s_tready";
        wait ()
      )
    in
    wait ();
    inputs.s_tvalid := Bits.gnd
  in

  let run_testcase ~id ~w ~h ~counts =
    let ref_sol = solve_reference ~width:w ~height:h ~gift_counts:counts in

    (* Reset DUT *)
    inputs.clock := Bits.gnd;
    inputs.clear := Bits.vdd;
    inputs.m_tready := Bits.vdd;
    Cyclesim.cycle sim;
    inputs.clear := Bits.gnd;
    Cyclesim.cycle sim;

    (* Send input: width, height, then 6 gift counts (one 8-bit word each) *)
    send_word w;
    send_word h;
    List.iter counts ~f:(fun c -> send_word c);

    (* Wait for result with timeout *)
    let timeout = 50000 in
    let finished = ref false in
    let result = ref false in
    let cycle_count = ref 0 in

    while not !finished && !cycle_count < timeout do
      if Bits.to_bool !(outputs.m_tvalid) then (
         finished := true;
         result := (Bits.to_int_trunc !(outputs.m_tdata) = 1);
      );
      incr cycle_count;
      Cyclesim.cycle sim;
    done;

    let status = if Bool.equal ref_sol !result then "PASS" else "FAIL" in
    Printf.printf "Test %2d: %2dx%2d Gifts:%d | %s\n" 
      id w h (List.fold counts ~init:0 ~f:(+)) status;
    Out_channel.flush stdout
  in

  print_endline "--- Starting Verification ---";

  let cases = [
    ( 0, 4, 4, [1;0;0;0;0;0]);
    ( 1, 6, 6, [0;1;0;0;0;0]);
    ( 2, 8, 8, [0;0;1;0;0;0]);
    ( 3, 5, 7, [0;0;0;1;0;0]);
    ( 4, 9, 5, [0;0;0;0;1;0]);
    ( 5, 12, 12, [2;1;0;0;0;0]);
    ( 6, 14, 14, [1;1;1;0;0;0]);
    ( 7, 16, 16, [2;2;0;0;0;0]);
    ( 8, 10, 14, [0;0;0;1;1;1]);
    ( 9, 13, 13, [1;0;1;0;1;1]);
    (10, 8, 8, [2;2;0;0;0;0]);
    (11, 6, 10,[1;1;1;1;0;0]);
    (12, 10, 6, [3;0;0;0;0;0]);
    (13, 7, 7, [0;2;2;0;0;0]);
    (14, 9, 9, [0;0;0;2;1;0]);
    (15, 4, 4, [5;0;0;0;0;0]);
    (16, 5, 5, [6;0;0;0;0;0]);
    (17, 4, 6, [7;0;0;0;0;0]);
    (18, 6, 4, [0;8;0;0;0;0]);
    (19, 5, 5, [4;3;2;0;0;0]);
  ] in

  List.iter cases ~f:(fun (id, w, h, counts) -> run_testcase ~id ~w ~h ~counts);

  [%expect {|
    --- Starting Verification ---
    Test  0:  4x 4 Gifts:1 | PASS
    Test  1:  6x 6 Gifts:1 | PASS
    Test  2:  8x 8 Gifts:1 | PASS
    Test  3:  5x 7 Gifts:1 | PASS
    Test  4:  9x 5 Gifts:1 | PASS
    Test  5: 12x12 Gifts:3 | PASS
    Test  6: 14x14 Gifts:3 | PASS
    Test  7: 16x16 Gifts:4 | PASS
    Test  8: 10x14 Gifts:3 | PASS
    Test  9: 13x13 Gifts:4 | PASS
    Test 10:  8x 8 Gifts:4 | PASS
    Test 11:  6x10 Gifts:4 | PASS
    Test 12: 10x 6 Gifts:3 | PASS
    Test 13:  7x 7 Gifts:4 | PASS
    Test 14:  9x 9 Gifts:3 | PASS
    Test 15:  4x 4 Gifts:5 | PASS
    Test 16:  5x 5 Gifts:6 | PASS
    Test 17:  4x 6 Gifts:7 | PASS
    Test 18:  6x 4 Gifts:8 | PASS
    Test 19:  5x 5 Gifts:9 | PASS
    |}]
;;
