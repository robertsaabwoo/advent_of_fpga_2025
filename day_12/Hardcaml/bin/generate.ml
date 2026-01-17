open! Core
open! Hardcaml
open! Hardcaml_demo_project

let generate_day_12_solver_rtl () =
  let module C = Circuit.With_interface (Day_12_solver.I) (Day_12_solver.O) in
  let scope = Scope.create ~auto_label_hierarchical_ports:true () in
  let circuit = C.create_exn ~name:"Day_12_solver_top" (Day_12_solver.hierarchical scope) in
  let rtl_circuits =
    Rtl.create ~database:(Scope.circuit_database scope) Verilog [ circuit ]
  in
  let rtl = Rtl.full_hierarchy rtl_circuits |> Rope.to_string in
  print_endline rtl
;;

let day_12_solver_rtl_command =
  Command.basic
    ~summary:""
    [%map_open.Command
      let () = return () in
      fun () -> generate_day_12_solver_rtl ()]
;;

let () =
  Command_unix.run
    (Command.group ~summary:"" [ "Day-12-solver", day_12_solver_rtl_command ])
;;
