:- module(db_delete,[
              try_delete_db/2,
              delete_db/2,
              force_delete_db/2
          ]).

/** <module> Database Deletion Logic
 *
 * Predicates for deleting databases
 *
 * * * * * * * * * * * * * COPYRIGHT NOTICE  * * * * * * * * * * * * * * *
 *                                                                       *
 *  This file is part of TerminusDB.                                     *
 *                                                                       *
 *  TerminusDB is free software: you can redistribute it and/or modify   *
 *  it under the terms of the GNU General Public License as published by *
 *  the Free Software Foundation, under version 3 of the License.        *
 *                                                                       *
 *                                                                       *
 *  TerminusDB is distributed in the hope that it will be useful,        *
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of       *
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the        *
 *  GNU General Public License for more details.                         *
 *                                                                       *
 *  You should have received a copy of the GNU General Public License    *
 *  along with TerminusDB.  If not, see <https://www.gnu.org/licenses/>. *
 *                                                                       *
 * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * */

:- reexport(core(util/syntax)).
:- use_module(core(util)).
:- use_module(core(triple)).
:- use_module(core(query)).
:- use_module(core(transaction)).

:- use_module(library(terminus_store)).

begin_deleting_db_from_system(Organization,DB_Name) :-
    create_context(system_descriptor{}, System),
    with_transaction(
        System,
        (   do_or_die(database_finalized(System,Organization,DB_Name),
                      error(database_not_finalized(Organization,DB_Name))),
            organization_database_name_uri(System,Organization,DB_Name,Db_Uri),
            ask(System,
                (   delete(Db_Uri, system:database_state, system:finalized, "instance/main"),
                    insert(Db_Uri, system:database_state, system:deleting, "instance/main")))
        ),
        _Meta_Data).

delete_db_from_system(Organization,DB) :-
    create_context(system_descriptor{}, System),
    with_transaction(
        System,
        (   organization_database_name_uri(System,Organization,DB,Db_Uri),
            ask(System,
                delete_object(Db_Uri))
        ),
        _Meta_Data).

/**
 * delete_db(+Organization,+DB_Name) is semidet.
 *
 * Deletes a database if it exists, fails if it doesn't.
 */
delete_db(Organization,DB_Name) :-
    create_context(system_descriptor{}, System),
    (   database_exists(System,Organization,DB_Name)
    <>  throw(database_does_not_exist(Organization,DB_Name))),
    % Do something here? User may need to know what went wrong

    do_or_die(
        database_finalized(System,Organization,DB_Name),
        error(database_not_finalized(Organization,DB_Name),
              context(delete_db/2))),

    begin_deleting_db_from_system(Organization,DB_Name),

    delete_database_label(Organization,DB_Name),

    delete_db_from_system(Organization,DB_Name).

delete_database_label(Organization,Db) :-
    db_path(Path),
    organization_database_name(Organization,Db,Composite_Name),
    www_form_encode(Composite_Name,Composite_Name_Safe),
    atomic_list_concat([Path,Composite_Name_Safe,'.label'], File_Path),

    (   exists_file(File_Path)
    ->  delete_file(File_Path)
    ;   throw(error(database_files_do_not_exist(Organization,Db),
                    context(delete_database_label/2)))
    ).

/* Force deletion of databases in an inconsistent state */
force_delete_db(Organization,DB) :-
    ignore(delete_db_from_system(Organization,DB)),
    catch(
        delete_database_label(Organization,DB),
        error(database_files_do_not_exist(_,_), _),
        true).

/*
 * try_delete_db(DB_URI) is det.
 *
 * Attempt to delete a database given its URI
 */
try_delete_db(Organization,DB) :-
    do_or_die(
        delete_db(Organization,DB),
        error(database_cannot_be_deleted(Organization,DB))).
