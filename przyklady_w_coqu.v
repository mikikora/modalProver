(* Wprowadzenia *)

Theorem koniunkcjaI : forall p q : Prop, p -> q -> p /\ q.
Proof.
  intros p q P Q. split.
  - apply P.
  - apply Q.
Qed.

Theorem alternatywaI : forall P Q : Prop, P -> P \/ Q.
Proof.
  intros P Q HP. left. apply HP.
Qed.

Theorem negacjaI : forall P : Prop, P -> ~~P.
Proof.
  intros P HP. unfold not. intro contra. 
  apply contra. apply HP.
Qed.

Theorem rownowaznoscI : forall P Q : Prop, (P <-> Q) -> (Q <-> P).
Proof.
  intros P Q H. destruct H as [H1 H2]. split; assumption.
Qed.

(* 
  Wprowadzenie implikacji: intro
  Wprowadzenie koniunkcji: split
  Wprowadzenie alternatywy: left, right
  Wprowadzenie negacji: unfold (bo negacja nie istnieje)
  Wprowadzenie równoważności: split (bo ona nie istnieje)
*)

(* Eliminacje *)

Theorem koniunkcjaE : forall P Q : Prop, P /\ Q -> P.
Proof.
  intros. destruct H as [H1 H2]. assumption.
Qed.

Theorem alternatywaE : forall P Q R : Prop, R -> P \/ Q -> R.
Proof.
  intros. destruct H0.
  - assumption.
  - assumption.
Qed.

(*
  Eliminacja koniunkcji: destruct
  Eliminacja alternatywy: destruct
  Eliminacja implikacji: apply
*)

