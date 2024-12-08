Require Import Regex2NFA.lib.PreGraph.
Require Import Regex2NFA.theories.regex.
Require Import Coq.Init.Datatypes.
Require Import Coq.ZArith.ZArith.
Require Import Coq.Strings.Ascii.
Require Import List.
From StateMonad.monaderror Require Import monadEbasic.

Import MonadwitherrDeno.
Import MonadNotation.
Import ListNotations.
Local Open Scope Z_scope.
Local Open Scope stmonad_scope.

Section NoGraph_NFA_DEF.

Definition get_new_vertex : program state Z := {|
  nrm := fun s1 n s2 =>
    s2.(max_v) = s1.(max_v) + 1 /\
    s2.(max_e) = s1.(max_e) /\
    n = max_v s2;
  err := fun s1 => False (* no error case *)
|}.

Definition pregraph_add_vertex {T} (g: @pg_nfa T) (v: Z) : program state (@pg_nfa T) := {|
  nrm :=
    fun s1 g' s2 =>
    let g1 := g.(pg) in
    let g2 := g'.(pg) in
    s1 = s2 /\
    g2.(evalid) = g1.(evalid) /\
    g2.(vvalid) = addValidFunc v g1.(vvalid) /\
    g2.(src) = g1.(src) /\
    g2.(dst) = g1.(dst);
  err := fun s1 => v > s1.(max_v) + 1
  (* error if new vertex label mismatches current state *)
|}.

Definition pregraph_add_new_vertex {T} (g: @pg_nfa T) : program state (@pg_nfa T) :=
  n <- get_new_vertex ;;
  pregraph_add_vertex g n.

Definition get_new_edge : program state Z := {|
  nrm :=
    fun s1 n s2 =>
    s2.(max_v) = s1.(max_v) /\
    s2.(max_e) = s1.(max_e) + 1 /\
    n = s2.(max_e);
  err := fun s1 => False (* no error case *)
|}.

(* add_vertex relation (g1 v g2)*)

Definition pregraph_add_edge {T} (g: @pg_nfa T) (e: Z) (s t: Z) : program state (@pg_nfa T) := {|
  nrm :=
    fun s1 g' s2 =>
    let g1 := g.(pg) in
    let g2 := g'.(pg) in
    s1 = s2 /\
    g2.(vvalid) = g1.(vvalid) /\
    g2.(evalid) = addValidFunc e g1.(evalid) /\
    g2.(src) = updateEdgeFunc g1.(src) e s /\
    g2.(dst) = updateEdgeFunc g1.(dst) e t;
  err :=
    fun s1 =>
    let g1 := g.(pg) in
    exists e',
    g1.(vvalid) s /\ g1.(vvalid) t /\
    g1.(evalid) e' /\
    g1.(src) e' = s /\
    g1.(dst) e' = t
  (* error if edge exists *)
|}.

Definition pregraph_add_new_edge {T} (g: @pg_nfa T) (s t: Z) : program state (@pg_nfa T) :=
  n <- get_new_edge ;;
  pregraph_add_edge g n s t.

Definition updateEdgeSymbol {T} (g: @pg_nfa T) (e: Z) (c: option T) : program state (@pg_nfa T) := {|
  nrm :=
    fun s1 g' s2 =>
    s1 = s2 /\
    g'.(symbol) = fun n => if Z.eqb e n then c else g.(symbol) n;
  err := fun s1 => False
|}.
(* Relation *)

Definition graph_union {T} (A B: @pg_nfa T) : program state pg_nfa := {|
  nrm :=
    fun s1 G s2 =>
    s1 = s2 /\
    G_union_rel A B G;
  err :=
    fun s1 => vertex_overlap A B \/ edge_overlap A B \/ symbol_overlap A B
|}.

Definition nfa_to_elem {T} (sv ev: Z) (g: @pg_nfa T) : program state elem := {|
  nrm :=
    fun s1 E s2 =>
    s1 = s2 /\
    E = {|
      startVertex := sv;
      endVertex := ev;
      graph := g
    |};
  err :=
    fun s1 =>
    ~ vvalid g.(pg) sv \/ ~ vvalid g.(pg) ev
|}.

(** *)

Definition pregraph_add_whole_edge {T} (g: @pg_nfa T) (s t: Z)
  (c: option T) : program state pg_nfa :=
  e <- get_new_edge ;;
  g1 <- pregraph_add_edge g e s t ;;
  updateEdgeSymbol g1 e c.

Inductive graph_construction_component {T} :=
  | G (g: @pg_nfa T)
  | V (v: Z)
  | E (v1 v2: Z) (sbl: option T).

Definition pregraph_add_component {T} (g: @pg_nfa T)
  (comp: graph_construction_component)
  : program state pg_nfa :=
  match comp with
  | G g' => graph_union g g'
  | V v => pregraph_add_vertex g v
  | E v1 v2 sbl => pregraph_add_whole_edge g v1 v2 sbl
  end
.

Fixpoint pregraph_merge_comp_list {T} (g: @pg_nfa T)
  (l_comp: list graph_construction_component)
  : program state pg_nfa :=
  match l_comp with
  | nil => return g
  | cons comp l_comp' =>
    g1 <- pregraph_add_component g comp ;;
    pregraph_merge_comp_list g1 l_comp'
  end
.

(** Regex operator definition (concat/union/star/...) *)

Definition act_empty {T} : program state (@elem T) :=
  v1 <- get_new_vertex ;;
  v2 <- get_new_vertex ;;
  g1 <- pregraph_merge_comp_list empty_nfa [V v1; V v2] ;;
  nfa_to_elem v1 v2 g1.

(* match single char c *)
Definition act_singleton {T} (c: option T) : program state elem :=
  v1 <- get_new_vertex ;;
  v2 <- get_new_vertex ;;
  g1 <- pregraph_merge_comp_list empty_nfa [V v1; V v2; E v1 v2 c] ;;
  nfa_to_elem v1 v2 g1.

(* match A|B *)
Definition act_union {T} (A B: @elem T) : program state elem :=
  v1 <- get_new_vertex ;;
  v2 <- get_new_vertex ;;
  g <- pregraph_merge_comp_list A.(graph) [G B.(graph);
                                            V v1;
                                            V v2;
                                            E v1 A.(startVertex) epsilon;
                                            E v1 B.(startVertex) epsilon;
                                            E A.(endVertex) v2 epsilon;
                                            E B.(endVertex) v2 epsilon] ;;
  nfa_to_elem v1 v2 g.

  (* 合并操作 get_new_edge, pregraph_add_edge, updateEdgeSymbol *)
  (* graph_construction : list graph_construction_component -> program state graph *)
  (* Inductive graph_construction_component :=  G (g: pg_nfa)
                                              | V (v: Z)
                                              | E (v1 v2: Z) (label: option ascii). *)
  (* list gr_constr_comp -> Monad *)

(* match AB *)
Definition act_concat {T} (A B: @elem T) : program state elem :=
  g <- pregraph_merge_comp_list A.(graph) [G B.(graph);
                                           E A.(endVertex) B.(startVertex) epsilon] ;;
  nfa_to_elem A.(startVertex) B.(endVertex) g.
  
(* match A* *)
Definition act_star {T} (A: @elem T) : program state elem :=
  let g := A.(graph) in
  v1 <- get_new_vertex ;;
  v2 <- get_new_vertex ;;
  g1 <- pregraph_merge_comp_list g [V v1;
                                    V v2;
                                    E v1 A.(endVertex) epsilon;
                                    E A.(endVertex) v2 epsilon;
                                    E A.(endVertex) A.(startVertex) epsilon] ;;
  nfa_to_elem v1 v2 g1.

(* match A+ *)
Definition act_plus {T} (A: @elem T) : program state elem :=
  let g := A.(graph) in
  v1 <- get_new_vertex ;;
  v2 <- get_new_vertex ;;
  g1 <- pregraph_add_vertex g v1 ;;
  g2 <- pregraph_add_vertex g1 v2 ;;
  g3 <- pregraph_add_whole_edge g2 v1 A.(startVertex) epsilon ;;
  g4 <- pregraph_add_whole_edge g3 A.(endVertex) v2 epsilon ;;
  g5 <- pregraph_add_whole_edge g4 A.(endVertex) A.(startVertex) epsilon ;;
  nfa_to_elem v1 v2 g5.

(* match A? *)
Definition act_question {T} (A: @elem T) : program state elem :=
  let g := A.(graph) in
  g1 <- pregraph_add_whole_edge g A.(startVertex) A.(endVertex) epsilon ;;
  nfa_to_elem A.(startVertex) A.(endVertex) g1.

(* Regex AST <-> NFA Monad *)

Fixpoint regexToNFA {T} (r : reg_exp T) : program state elem :=
  match r with
  (** 2 vertices *)
  | EmptySet_r => act_empty

  | EmptyStr_r => act_singleton None

  | Char_r t => act_singleton (Some t)

  | Concat_r r1 r2 =>
    E1 <- regexToNFA r1 ;;
    E2 <- regexToNFA r2 ;;
    act_concat E1 E2

  | Union_r r1 r2 =>
    E1 <- regexToNFA r1 ;;
    E2 <- regexToNFA r2 ;;
    act_union E1 E2

  | Star_r r =>
    E <- regexToNFA r ;;
    act_star E
  end.

End NoGraph_NFA_DEF.


(** 1. st_nograph <-> regex *)

(** NFA accepts a string ? *)
