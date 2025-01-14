(* Copyright (C) 2017--2021  Petter A. Urkedal <paurkedal@gmail.com>
 *
 * This library is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or (at your
 * option) any later version, with the LGPL-3.0 Linking Exception.
 *
 * This library is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
 * License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * and the LGPL-3.0 Linking Exception along with this library.  If not, see
 * <http://www.gnu.org/licenses/> and <https://spdx.org>, respectively.
 *)

(** Request specification.

    A Caqti request is a function to generate a query string from information
    about the driver, along with type descriptors to encode parameters and
    decode rows returned from the same query.  Requests are passed to
    {!Caqti_connection_sig.S.call} or one of its shortcut methods provided by a
    database connection handle.

    The request often represent a prepared query, in which case it is static and
    can be defined directly in a module scope.  However, an optional [oneshot]
    parameter may be passed to indicate a dynamically generated query. *)

(** {2 Primitives} *)

(**/**)
[@@@warning "-3"]
type query = Caqti_query.t =
  | L of string [@deprecated "Moved to Caqti_query"]
  | Q of string [@deprecated "Moved to Caqti_query"]
  | P of int [@deprecated "Moved to Caqti_query"]
  | S of query list [@deprecated "Moved to Caqti_query"]
[@@deprecated "Moved to Caqti_query.t"]
[@@@warning "+3"]
(**/**)

type ('a, 'b, +'m) t constraint 'm = [< `Zero | `One | `Many]
(** A request specification embedding a query generator, parameter encoder, and
    row decoder.
    - ['a] is the type of the expected parameter bundle.
    - ['b] is the type of a returned row.
    - ['m] is the possible multiplicities of returned rows. *)

val create :
  ?oneshot: bool ->
  'a Caqti_type.t -> 'b Caqti_type.t -> 'm Caqti_mult.t ->
  (Caqti_driver_info.t -> Caqti_query.t) -> ('a, 'b, 'm) t
(** [create arg_type row_type row_mult f] is a request which takes parameters of
    type [arg_type], returns rows of type [row_type] with multiplicity
    [row_mult], and which sends query strings generated from the query [f di],
    where [di] is the {!Caqti_driver_info.t} of the target driver.  The driver
    is responsible for turning parameter references into a form accepted by the
    database, while other differences must be handled by [f].

    @param oneshot
      Disables caching of a prepared statements on connections for this query.

        - If false (the default), the statement is prepared and a handle is
          permanently attached to the connection object right before the first
          time it is executed.

        - If true, everything allocated in order to execute the statement is
          released after use.

      In other words, the default is suitable for queries which are bound to
      static modules.  Conversely, you should pass [~oneshot:true] if the query
      is dynamically generated, whether it is within a function or a dynamic
      module, since there will otherwise be a memory leak associated with
      long-lived connections.  You might as well also pass [~oneshot:true] if
      you know that the query will only executed at most once (or a very few
      times) on each connection. *)

val param_type : ('a, _, _) t -> 'a Caqti_type.t
(** [param_type req] is the type of parameter bundles expected by [req]. *)

val row_type : (_, 'b, _) t -> 'b Caqti_type.t
(** [row_type req] is the type of rows returned by [req]. *)

val row_mult : (_, _, 'm) t -> 'm Caqti_mult.t
(** [row_mult req] indicates how many rows [req] may return.  This is asserted
    when constructing the query. *)

val query_id : ('a, 'b, 'm) t -> int option
(** If [req] is a prepared query, then [query_id req] is [Some id] for some [id]
    which uniquely identifies [req], otherwise it is [None]. *)

val query : ('a, 'b, 'm) t -> Caqti_driver_info.t -> Caqti_query.t
(** [query req] is the function which generates the query of this request
    possibly tailored for the given driver. *)

(** {2 Convenience}

    In the following functions, queries are written out as plain strings with
    the following syntax, which is parsed by Caqti into a {!Caqti_query.t}
    object before being passed to drivers.

    {b Parameters} are specified as either

    - ["?"] for linear substitutions (like Sqlite and MariaDB), or
    - ["$1"], ["$2"], ... for non-linear substitutions (like PostgreSQL).

    Either case works independent of the style used by the database system; if
    non-linear substitutions are used with a database system which does not
    support it, the parameter values will be reorderd and duplicated as needed.
    Mixing the two styles in the same query string is not permitted.  Note that
    numbering of non-linear parameters is offset by one compared to
    {!Caqti_query.P}, in order to be consistent with PostgreSQL conventions.

    {b Static references} are references to the [?env] argument of the functions
    below, and thus fixed once the query has been constructed.  The query parser
    accepts two forms:

    - ["$(<var>)"] is substituted by [env driver_info "<var>"].
    - ["$(<var>.)"], if not found by the first rule, is substituted by
      [env driver_info "<var>"] followed by a dot iff that result is nonempty.
    - ["$<var>."] is a shortcut for ["$(<var>.)"].

    These aid in substituting configurable fragments, like database schemas or
    table names.  The latter form is suggested for qualifying tables, sequences,
    etc. with the main database schema.  It should expand to a schema name
    followed by a dot, so that the empty string can be returned if the database
    does not support schemas or no schema is requested by the user.

    Finally,

    - Dollar signs in single-quoted strings are left unchanged.
    - ["$<var>$"] is left unchanged.
    - ["$$"] will be left unchanged in future versions, see the notice below.

    Apart from the more generic {!create_p}, these function match up with
    retrieval functions of {!Caqti_connection_sig.S} and {!Caqti_response_sig.S}
    according to the multiplicity parameter of their types.

    {b Deprecation of undocumented feature.} It has been possible to quote the
    dollar sign by doubling it. This was undocumented and is hereby deprecated.
    If you need a literal dollar signs outside quoted strings, add a variable
    which expands to the dollar sign to the environment. *)

val create_p :
  ?env: (Caqti_driver_info.t -> string -> Caqti_query.t) ->
  ?oneshot: bool ->
  'a Caqti_type.t -> 'b Caqti_type.t -> 'm Caqti_mult.t ->
  (Caqti_driver_info.t -> string) -> ('a, 'b, 'm) t
(** [create_p arg_type row_type row_mult f] is a request which takes parameters
    of type [arg_type], returns rows of type [row_type] with multiplicity
    [row_mult], and which sends a query string based on a preliminary form given
    by [f di], where [di] is the {!Caqti_driver_info.t} of the target driver.
    The preliminary query string may contain parameter and static references as
    described in the introduction of this section.

    @param oneshot
      Disables caching of a prepared statements on connections for this query.
      See {!create} for details.

    @param env
      [env driver_info key] shall provide the value to substitute for a
      reference to [key] in the preliminary query string, or raise [Not_found]
      to indicate the reference to [key] is invalid.  [Not_found] will be
      re-raised as [Invalid_argument] with additional information to help locate
      the bug. *)

val exec :
  ?env: (Caqti_driver_info.t -> string -> Caqti_query.t) ->
  ?oneshot: bool ->
  'a Caqti_type.t ->
  string -> ('a, unit, [> `Zero]) t
(** [exec_p ?env ?oneshot arg_type s] is a shortcut for [create_p ?env ?oneshot
    arg_type Caqti_type.unit Caqti_mult.zero (fun _ -> s)]. *)

val find :
  ?env: (Caqti_driver_info.t -> string -> Caqti_query.t) ->
  ?oneshot: bool ->
  'a Caqti_type.t -> 'b Caqti_type.t ->
  string -> ('a, 'b, [> `One]) t
(** [find_p ?env ?oneshot arg_type row_type s] is a shortcut for
    [create_p ?env ?oneshot arg_type row_type Caqti_mult.one (fun _ -> s)]. *)

val find_opt :
  ?env: (Caqti_driver_info.t -> string -> Caqti_query.t) ->
  ?oneshot: bool ->
  'a Caqti_type.t -> 'b Caqti_type.t ->
  string -> ('a, 'b, [> `Zero | `One]) t
(** [find_opt_p arg_type ?env ?oneshot row_type s] is a shortcut for [create_p
    ?env ?oneshot arg_type row_type Caqti_mult.zero_or_one (fun _ -> s)]. *)

val collect :
  ?env: (Caqti_driver_info.t -> string -> Caqti_query.t) ->
  ?oneshot: bool ->
  'a Caqti_type.t -> 'b Caqti_type.t ->
  string -> ('a, 'b, [> `Zero | `One | `Many]) t
(** [collect_p arg_type ?env ?oneshot row_type s] is a shortcut for
    [create_p arg_type ?env ?oneshot row_type Caqti_mult.many (fun _ -> s)]. *)

val pp : Format.formatter -> ('a, 'b, 'm) t -> unit
(** [pp ppf req] prints [req] on [ppf] in a form suitable for human
    inspection. *)

val pp_with_param :
  ?driver_info: Caqti_driver_info.t ->
  Format.formatter -> ('a, 'b, 'm) t * 'a -> unit
(** [pp_with_param ppf (req, param)] prints [req] and the associated [param] to
    [ppf].  This functions is meant for debugging; the output is neither
    guaranteed to be consistent across releases nor to contain a complete record
    of the data.

    Due to concerns about exposure of sensitive data in debug logs, this
    function reverts to {!pp} unless the environment varibale
    [CAQTI_DEBUG_PARAM] is set to [true]. If you enable it for applications
    which do not consistenly annotate sensitive parameters with
    {!Caqti_type.redact}, make sure your debug logs are well secured. *)

(** {2 How to Dynamically Assemble Queries and Parameters}

    In some cases, queries are constructed dynamically, e.g. when translating an
    expression for searching a database into SQL.  In such cases the number of
    parameters and their types will typically vary, as well.  A helper like the
    following can be used to existentially pack the parameter types along with
    the corresponding parameter values to allow collecing them incrementally:
    {[
      module Dynparam = struct
        type t = Pack : 'a Caqti_type.t * 'a -> t
        let empty = Pack (Caqti_type.unit, ())
        let add t x (Pack (t', x')) = Pack (Caqti_type.tup2 t' t, (x', x))
      end
    ]}
    Now, given a [param : Dynparam.t] and a corresponding query string [qs], one
    can construct a request and execute it:
    {[
      let Dynparam.Pack (pt, pv) = param in
      let req = Caqti_request.exec ~oneshot:true pt qs in
      C.exec req pv
    ]}
    Note that dynamically constructed requests should have [~oneshot:true]
    unless they are memoized.  Also note that it is natural to use {!create} for
    dynamically constructed queries, since it accepts the easily composible
    {!Caqti_query.t} type instead of plain strings.

    This scheme can be specialized for particular use cases, including
    generation of fragments of the [query], which reduces the risk of wrongly
    matching up parameters with their uses in the query string.
    *)
