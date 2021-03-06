open Pos
open Err
open Tast
open Pseudocode

(* Convenience *)

let make_blit p n =
  ((if n then True else False), BaseET(p @> Bool, p @> Fixed Public))

let make_nlit p n =
  (IntLiteral n, BaseET(p @> Num(abs n, n < 0), p @> Fixed Public))


(* Simple Predicates *)

let is_int =
  xwrap @@ fun p -> function
    | UInt _ -> true
    | Int _ -> true
    | Num _ -> true
    | Bool -> false
    | UVec _ -> true

let is_signed' = function
  | Int _ -> true
  | UInt _ -> false
  | Num(_,s) -> s
  | Bool -> false
  | UVec _ -> false
let is_signed = unpack is_signed'

let numbits' = function
  | UInt n
  | Int n -> n
  | Bool -> 1
  | Num(i,s) ->
    if s || (i < 0) then
      let rec numbits_helper = function
        | n when n >= -128 && n <= 127 -> 8
        | n -> 8 + (numbits_helper (n / 256))
      in
        numbits_helper i
    else
      let rec numbits_helper = function
        | n when n >= 0 && n <= 255 -> 8
        | n -> 8 + (numbits_helper (n / 256))
      in
        numbits_helper i
let numbits = unpack numbits'

let is_bool =
  xwrap @@ fun p -> function
    | Bool -> true
    | _ -> false

let is_vec =
  xwrap @@ fun p -> function
    | UVec _ -> true
    | _ -> false

let is_array =
  xwrap @@ fun p -> function
    | BaseET _ -> false
    | ArrayET _ -> true


(* Extraction *)

let type_of' : (expr -> expr_type') =
  xwrap @@ fun p -> function
    | (_,ty) -> ty
let type_of = rebind type_of'

let atype_of : (array_expr -> expr_type) =
  xwrap @@ fun p -> function
    | (_,ty) -> p @> ty

let atype_to_btype =
  xwrap @@ fun p -> function
    | ArrayAT(b,_) -> b

let type_out =
  xwrap @@ fun p -> function
    | BaseET(b,ml) -> (b,ml)
    | ArrayET(a,ml,_) -> (atype_to_btype a,ml)

let expr_to_btype : (expr -> base_type) =
  xwrap @@ fun p -> function
    | (_,BaseET(b,_)) -> b
    | (_,ArrayET _) -> raise @@ cerr("expected a base type, got an array instead", p)

let expr_to_ml : (expr -> maybe_label) =
  xwrap @@ fun p -> function
    | (_,BaseET(_,ml)) -> ml

let expr_to_types : (expr -> base_type * maybe_label) =
  xwrap @@ fun p -> function
    | (_,BaseET(b,ml)) -> b,ml
    | (_,ArrayET _) -> raise @@ cerr("expected a base type, got an array instead", p)

let atype_out =
  xwrap @@ fun p -> function
    | ArrayET(a,ml,_) -> a,ml

let aetype_to_lexpr' =
  xwrap @@ fun p -> function
    | ArrayET(a,ml,m) ->
      let ArrayAT(bt,lexpr) = a.data in
        lexpr.data

let refvt_to_betype' =
  xwrap @@ fun p -> function
    | ArrayVT(a,ml,m,_) ->
      let ArrayAT(bt,lexpr) = a.data in
        BaseET(bt,ml)
let refvt_to_betype = rebind refvt_to_betype'

let arrayvt_to_refvt =
  wrap @@ fun p -> function
    | RefVT _ -> raise @@ cerr("expected an array, got a base type instead", p)
    | ArrayVT(a,ml,m,_) ->
      let ArrayAT(bt,lexpr) = a.data in
        RefVT(bt,ml,m)

let refvt_type_out =
  xwrap @@ fun p -> function
    | RefVT(b,ml,m) -> b,ml,m
    | ArrayVT(a,ml,m,_) -> (atype_to_btype a),ml,m

let refvt_mut_out' = function
  | RefVT(_,_,m) -> m
  | ArrayVT(_,_,m,_) -> m
  | StructVT(_,m) -> m

let refvt_to_lexpr =
  xwrap @@ fun p -> function
    | ArrayVT(a,ml,m,_) ->
      let ArrayAT(bt,lexpr) = a.data in
        lexpr

let refvt_to_lexpr_option =
  xwrap @@ fun p -> function
    | RefVT _ -> None
    | ArrayVT(a,ml,m,_) ->
      let ArrayAT(bt,lexpr) = a.data in
        Some lexpr.data
    | StructVT _ -> None

let refvt_to_etype' =
  xwrap @@ fun p -> function
    | RefVT(b,ml,_) -> BaseET(b, ml)
    | ArrayVT(a,ml,m,_) -> ArrayET(a, ml, m)
let refvt_to_etype = rebind refvt_to_etype'

let fname_of =
  xwrap @@ fun p -> function
    | FunDec(fname,_,_,_,_)
    | CExtern(fname,_,_)
    | DebugFunDec(fname,_,_) -> fname

let sname_of =
  xwrap @@ fun p -> function
    | Struct(sname,_) -> sname

(* Subtyping *)

let (<:) { data=b1 } { data=b2 } =
  match b1,b2 with
    | UInt n, UInt m when n <= m -> true
    | Int n, Int m when n <= m -> true
    | Bool, Bool -> true
    | Num(k,s), Int n -> true
    | Int n, Num(k,s) -> true
    | Num(k,s), UInt n when not s -> true
    | UInt n, Num(k,s) when not s -> true
    | a, b when a = b -> true
    | _ -> false

let (=:) { data=b1 } { data=b2 } =
  match b1,b2 with
    | Num _, UInt _
    | Num _, Int _
    | UInt _, Num _
    | Int _, Num _ -> true
    | a, b when a = b -> true
    | _ -> false

let (<::) { data=ArrayAT(b1,lx1) } { data=ArrayAT(b2,lx2) } =
  let lxmatch =
    match lx1.data,lx2.data with
      | LIntLiteral n, LIntLiteral m when n = m -> true
      | LDynamic x, LDynamic y when x.data = y.data -> true
      | _ -> false in
    lxmatch && (b1 =: b2)

let joinable_bt b1 b2 =
  (b1 <: b2) || (b2 <: b1)

let join_bt p { data=b1 } { data=b2 } =
  let b' =
    match b1,b2 with
      | UInt n, UInt m -> UInt (max n m)
      | Int n, Int m -> Int (max n m)
      | Bool, Bool -> b1
      | Num(k,s), Int n -> b2
      | Int n, Num(k,s) -> b1
      | Num(k,s), UInt n -> b2
      | UInt n, Num(k,s) -> b1
      | String, String -> b1
      | Num(k1,s1), Num(k2,s2) -> Num(max k1 k2,s1 || s2) (* XXX max k1 k2 makes no sense *)
      | a, b when a = b -> a
      | _ -> raise @@ cerr("type mismatch: " ^ show_base_type' b1 ^ " <> " ^ show_base_type' b2, p);
  in p @> b'

let min_bt p { data=b1 } { data=b2 } =
  let b' =
    match b1,b2 with
      | UInt n, UInt m -> UInt (min n m)
      | Int n, Int m -> Int (min n m)
      | Num(k,s), Int n -> b2
      | Int n, Num(k,s) -> b1
      | Num(k,s), UInt n ->
        let m = numbits' b1 in
          UInt (min n m)
      | UInt n, Num(k,s) ->
        let m = numbits' b2 in
          UInt (min n m)
      | Num(k1,s1), Num(k2,s2) -> Num(max k1 k2,s1 || s2) (* XXX max k1 k2 makes no sense *)
      | _ -> raise @@ cerr("invalid types for min_bt: " ^ show_base_type' b1 ^ " <> " ^ show_base_type' b2, p);
  in p @> b'

let meet_bt p { data=b1 } { data=b2 } =
  let b' =
    match b1,b2 with
      | UInt n, UInt m when n = m -> b1
      | Int n, Int m when n = m -> b1
      | Bool, Bool -> b1
      | Num(k,s), Int n -> b2
      | Int n, Num(k,s) -> b1
      | Num(k,s), UInt n when k >= 0 -> b2
      | UInt n, Num(k,s) when k >= 0 -> b1
      | String, String -> b1
      | Num(k1,s1), Num(k2,s2) -> Num(max k1 k2,s1 || s2)
      | _ -> raise @@ err(p)
  in p @> b'

let (<$.) l1 l2 =
  match l1,l2 with
    | x, y when x = y -> true
    | Public, Secret -> true
    | _ -> false

let (+$.) l1 l2 =
  match l1,l2 with
    | Public, Public -> Public
    | Public, Secret -> Secret
    | Secret, Public -> Secret
    | Secret, Secret -> Secret

let (<$) { data=ml1 } { data=ml2 } =
  match ml1,ml2 with
    | Fixed x, Fixed y -> x <$. y
    | _ -> false

let join_ml p { data=ml1 } { data=ml2 } =
  let ml' =
    match ml1,ml2 with
      | Fixed x, Fixed y -> Fixed (x +$. y)
      | _ -> raise @@ err(p)
  in p @> ml'

let (<:$) ty1 ty2 =
  match (is_array ty1),(is_array ty2) with
    | false, false ->
      let b1,ml1 = type_out ty1 in
      let b2,ml2 = type_out ty2 in
        (b1 <: b2) && (ml1 <$ ml2)
    | _ -> false

let join_ty' p ty1 ty2 =
  let b1,ml1 = type_out ty1 in
  let b2,ml2 = type_out ty2 in
  let b' = join_bt p b1 b2 in
  let ml' = join_ml p ml1 ml2 in
    BaseET(b', ml')

let (<*) m1 m2 =
  match m1,m2 with
    | Const, Mut -> false (* can't alias a const as a mut *)
    | _ -> true

let check_can_be_passed_to { pos=p; data=argty} {data=paramty} =
  match argty, paramty with
    | RefVT(_,_,m1), RefVT(_,_,m2)
      when m1.data <> m2.data ->
      raise @@ cerr(Printf.sprintf
                      "cannot pass %s to %s%s"
                      (ps_mut_full m1)
                      (ps_mut_full m2)
                      (if m2.data = Mut then
                         " (did you forget a `ref`?)"
                       else ""), p)
    | RefVT(b1,l1,_), RefVT(b2,l2,_) ->
      if not (b1 <: b2) then
        raise @@ cerr(Printf.sprintf
                        "cannot pass %s to %s"
                        (ps_bty b1)
                        (ps_bty b2), p);
      if not (l1 <$ l2) then
        raise @@ cerr(Printf.sprintf
                        "cannot pass %s to %s"
                        (ps_label l1)
                        (ps_label l2), p);
      ()
    | ArrayVT(a1,l1,m1,_), ArrayVT(a2,l2,m2,_) ->
      let ArrayAT(b1,lx1), ArrayAT(b2,lx2) = a1.data, a2.data in
      let lxmatch =
        match lx1.data, lx2.data with
          | _, LDynamic _ -> true
          | LIntLiteral n, LIntLiteral m when n = m -> true
          | _ -> false
      in
        if b1.data <> b2.data then
          raise @@ cerr(Printf.sprintf
                          "incompatible array base types: %s vs %s"
                          (ps_bty b1)
                          (ps_bty b2), p);
        if not lxmatch then raise @@ cerr(Printf.sprintf
                                            "incompatible lengths: %s vs %s"
                                            (ps_lexpr_for_err lx1)
                                            (ps_lexpr_for_err lx2), p);
        begin
          match m1.data, m2.data with
            | Const, Const ->
              if not (l1 <$ l2) then
                raise @@ cerr(Printf.sprintf
                                "cannot pass %s to %s"
                                (ps_label l1)
                                (ps_label l2), p)
            | Mut, Mut ->
              if not (l1.data = l2.data) then
                raise @@ cerr(Printf.sprintf
                                "cannot pass mut %s to mut %s"
                                (ps_label l1)
                                (ps_label l2), p)
            | _ -> raise @@ cerr(Printf.sprintf
                                   "cannot pass %s to %s%s"
                                   (ps_mut_full m1)
                                   (ps_mut_full m2)
                                   (if m2.data = Mut then
                                      " (did you forget a `ref`?)"
                                    else ""), p)
        end
    | StructVT _, StructVT _ -> () (* XXX fix this later *)
    | _ -> raise @@ cerr("attempting to pass incompatible type", p)

let (<:$*) (ty1,is_new_mem) ty2 =
  let ArrayET(a1,l1,m1) = ty1.data in
  let ArrayET(a2,l2,m2) = ty2.data in
  let ArrayAT(b1,lx1), ArrayAT(b2,lx2) = a1.data, a2.data in
  let lxmatch =
    match lx1.data, lx2.data with
      | _, LDynamic _ -> true
      | LIntLiteral n, LIntLiteral m when n = m -> true
      | _ -> false
  in
    (b1 <: b2) &&
    lxmatch &&
    (match m1.data, m2.data with
      | Const, Const -> l1 <$ l2
      | Mut, Const -> l1 <$ l2
      | Const, Mut -> is_new_mem && l1 <$ l2
      | Mut, Mut -> l1.data = l2.data
    )


(* Complex Predicates *)

let is_expr_secret e =
  let { data=(_,BaseET(_,{data=Fixed l})) } = e in
    l = Secret

let param_is_ldynamic =
  xwrap @@ fun p -> function
    | Param(_,{data=vty'},_) ->
      begin
        match vty' with
          | ArrayVT({data=ArrayAT(_,{data=LDynamic _})},_,_,_) -> true
          | _ -> false
      end


(* Simple Manipulation *)

let atype_update_lexpr lexpr' =
  wrap @@ fun p -> function
    | ArrayAT(bt,_) -> ArrayAT(bt, p @> lexpr')

let aetype_update_lexpr' lexpr' =
  xwrap @@ fun p -> function
    | ArrayET(a,ml,m) ->
      ArrayET(atype_update_lexpr lexpr' a, ml, m)

let aetype_update_mut' mut = function
  | ArrayET(a,ml,_) -> ArrayET(a, ml, mut)

let refvt_update_mut' mut =
  xwrap @@ fun p -> function
    | RefVT(b,ml,_) -> RefVT(b, ml, mut)
    | ArrayVT(a,ml,_,attr) -> ArrayVT(a, ml, mut, attr)
    | StructVT(s,_) -> StructVT(s, mut)


(* Structs *)

let has_struct sdecs s =
  List.exists (fun {data=Struct(sn,_)} -> s.data = sn.data) sdecs

let find_struct sdecs s =
  List.find (fun {data=Struct(sn,_)} -> s.data = sn.data) sdecs

let rec struct_has_secrets sdecs s =
  let sdec = find_struct sdecs s in
  let Struct(_,fields) = sdec.data in
    List.exists
      (fun {data=Field(_,vt,_)} ->
         match vt.data with
           | RefVT(_,{data=Fixed label},_) -> label = Secret
           | ArrayVT(_,{data=Fixed label},_,_) -> label = Secret
           | StructVT(sn,_) -> struct_has_secrets sdecs sn
      )
      fields

