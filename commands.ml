open Ast
open Proof
open Format
open Proof_syntax
open Error

type current_proof = P of proof | G of goal

let current_proof : current_proof list ref = ref []
let current_proof_name : string option ref = ref None
let current_system : Relation.system option ref = ref None
let last_declared_relation : Relation.relation_name option ref = ref None

let theorem_to_prove : (string * string * Syntax.judgement) option ref =
  ref None

let command_history : command list ref = ref []
let theorem_map : (string, Syntax.theorem) Hashtbl.t = Hashtbl.create 5
let get_proven_theorems () = Hashtbl.to_seq theorem_map
let get_current_proof_for_backup () = (!theorem_to_prove, !command_history)
let add_theorem_from_backup = Hashtbl.add theorem_map

let rec cmd_to_proof_function : command -> goal -> goal = function
  | IntroCmd (name, world) -> intro name world
  | ApplyCmd (name1, name2, world, jgmt) -> apply name1 name2 world jgmt
  | ApplyAssmCmd (name1, name2, world, name) -> (
      fun goal ->
        try apply_assm name1 name2 world name goal
        with Not_found -> (
          try apply_th name1 name2 world (Hashtbl.find theorem_map name) goal
          with Not_found -> raise (UnlocatedError (name ^ " not found"))))
  | SplitCmd -> split
  | LeftCmd -> left
  | RightCmd -> right
  | ContraCmd w -> contra w
  | SerialCmd (name, world, world1) -> serial name world world1
  | ReflCmd (name, world) -> refl name world
  | SymmCmd (name, world1, world2) -> symm name world1 world2
  | TransCmd (name, world1, world2, world3) -> trans name world1 world2 world3
  | EuclCmd (name, world1, world2, world3) -> eucl name world1 world2 world3
  | DirectCmd (name1, name2, world1, world2, world3, world) ->
      direct name1 name2 world1 world2 world3 world
  | AssumptionCmd -> assumption
  | ChainCmd (cmd1, cmd2) ->
      let translate_cmd1 = cmd_to_proof_function cmd1
      and translate_cmd2 = cmd_to_proof_function cmd2 in
      chain_tactic translate_cmd1 translate_cmd2
  | TryCmd cmd -> try_tactic @@ cmd_to_proof_function cmd
  | _ -> raise (UnlocatedError "This is not a tactic")

let interpret_command cmd =
  let get_goal () =
    match List.hd !current_proof with
    | G gl -> gl
    | _ -> raise (UnlocatedError "Not focused")
  in
  match cmd with
  | AbandonCmd ->
      current_proof := [];
      current_proof_name := None;
      command_history := [];
      theorem_to_prove := None
  | QedCmd ->
      let cur_th =
        try List.hd !current_proof
        with Failure _ -> raise (UnlocatedError "No proof to complete")
      in
      let complete_theorem =
        match cur_th with
        | P pf -> qed pf
        | G _ -> raise (UnlocatedError "Proof is not complete")
      in
      Hashtbl.add theorem_map (Option.get !current_proof_name) complete_theorem;
      Relation.make_relation_unmutable (Syntax.relation complete_theorem);
      current_proof := [];
      current_proof_name := None;
      command_history := [];
      theorem_to_prove := None
  | ProofCmd -> (
      try
        match List.hd !current_proof with
        | P (Empty goal_desc) ->
            current_proof := G (focus 1 (Empty goal_desc)) :: !current_proof
        | P _ | G _ ->
            raise (UnlocatedError "Proof statement starts fresh proof")
      with Failure _ -> raise (UnlocatedError "Nothing to proof"))
  | FocusCmd n -> (
      try
        match List.hd !current_proof with
        | P pf -> current_proof := G (focus n pf) :: !current_proof
        | G _ -> raise (UnlocatedError "Can't focus while in active goal")
      with Failure _ -> raise (UnlocatedError "Nothing to focus to"))
  | UnfocusCmd -> (
      try
        match List.hd !current_proof with
        | G gl -> current_proof := P (unfocus gl) :: !current_proof
        | P _ -> raise (UnlocatedError "Already unfocused")
      with Failure _ -> raise (UnlocatedError "Nothing to unfocus from"))
  | UndoCmd -> (
      try current_proof := List.tl !current_proof with Failure _ -> ())
  | AutoCmd n ->
      let new_pf, new_path = Auto.auto cmd_to_proof_function n (get_goal ()) in
      if no_goals new_pf = 0 then
        let res = unfocus (new_pf, new_path) in
        if no_goals res = 1 then
          current_proof := G (focus 1 res) :: !current_proof
        else current_proof := P res :: !current_proof
      else ()
  | ApplyAssmCmd _ | AssumptionCmd | ChainCmd _ ->
      let res = unfocus @@ (cmd_to_proof_function cmd) (get_goal ()) in
      if no_goals res = 1 then
        current_proof := G (focus 1 res) :: !current_proof
      else current_proof := P res :: !current_proof
  | _ ->
      current_proof :=
        G ((cmd_to_proof_function cmd) (get_goal ())) :: !current_proof

let interpret_statement statement =
  match !current_proof with
  | [] -> (
      try
        match statement.v with
        | RelDecl (name, properties) ->
            Relation.add_new_relation name properties;
            last_declared_relation := Some name
        | RelProperties (name, properties) ->
            Relation.add_properties name properties
        | RelRmProperties (name, properties) ->
            Relation.remove_properties name properties
        | TheoremDecl (name, rel_opt, jgmt) ->
            let rel_name =
              match rel_opt with
              | None -> (
                  match !last_declared_relation with
                  | None ->
                      raise
                        (Error { v = "No relation declared"; l = statement.l })
                  | Some rel -> rel)
              | Some rel ->
                  if Relation.relation_exists rel then rel
                  else
                    raise
                      (Error
                         {
                           v = "Relation " ^ rel ^ " not declared";
                           l = statement.l;
                         })
            in
            theorem_to_prove := Some (name, rel_name, jgmt);
            current_proof := [ P (proof rel_name [] jgmt) ];
            current_proof_name := Some name
        | EnterModel (rel_opt, sys) ->
            last_declared_relation :=
              Some (Relation.create_relation_for_system rel_opt sys);
            current_system := Some sys
        | ExitModel -> (
            match !current_system with
            | None -> raise (Error { v = "No model to exit"; l = statement.l })
            | Some _ -> current_system := None)
        | _ ->
            raise
              (Error
                 { v = "Can't use that outsite proof mode"; l = statement.l })
      with
      | Relation.RelationDoesNotExist msg ->
          raise (Error { v = msg; l = statement.l })
      | Relation.Error (name, msg) ->
          let new_msg = name ^ " : " ^ msg in
          raise (Error { v = new_msg; l = statement.l }))
  | _ -> (
      match statement.v with
      | Command c -> (
          try
            interpret_command c;
            (if c = UndoCmd then
             try command_history := List.tl !command_history with _ -> ());
            if c <> QedCmd && c <> AbandonCmd && c <> UndoCmd then
              command_history := c :: !command_history
          with UnlocatedError msg ->
            let loc = statement.l in
            raise (Error { v = msg; l = loc }))
      | _ ->
          raise (Error { v = "Can't use that in open proof"; l = statement.l }))

let print_current_state print_hints =
  let print_command_prompt () =
    print_newline ();
    print_string (String.make 40 '=');
    print_newline ();
    print_string ">";
    print_flush ()
  in
  (match !current_system with
  | None -> ()
  | Some sys ->
      print_endline ("Active model: " ^ Relation.system_to_string sys ^ "\n"));
  try
    match List.hd !current_proof with
    | P pf ->
        print_unfocused_proof pf;
        print_command_prompt ()
    | G gl ->
        print_current_goal gl;
        if print_hints then (
          print_newline ();
          print_string (String.make 40 '=');
          print_newline ();
          let goal_desc =
            match gl with
            | Empty goal_desc, _ -> goal_desc
            | _ -> failwith "Not in empty goal"
          in
          print_endline "Hints:\n";
          print_string (Hint.get_hint_string goal_desc));
        print_command_prompt ()
  with Failure _ ->
    open_vbox 0;
    print_string "Declared relations:";
    print_cut ();
    Seq.iter
      (fun (relation : Relation.relation) ->
        print_string relation.name;
        if relation.properties = [] then () else print_string " : ";
        open_hbox ();
        List.iter
          (fun (property : Relation.rel_property) ->
            print_string @@ Relation.property_to_string property;
            print_string ",";
            print_space ())
          relation.properties;
        close_box ();
        print_cut ())
      (Relation.get_declared_relations ());
    print_string (String.make 40 '-');
    print_cut ();
    print_string "Complited theorems:";
    print_cut ();
    Hashtbl.iter
      (fun name th ->
        match Syntax.consequence th with
        | J (_, prop) ->
            open_hbox ();
            print_string (name ^ " [" ^ Syntax.relation th ^ "] : ");
            Syntax.print_prop prop;
            close_box ();
            print_cut ()
        | _ -> failwith "Absurd")
      theorem_map;
    close_box ();
    print_command_prompt ()
