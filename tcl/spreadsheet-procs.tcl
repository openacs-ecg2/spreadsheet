ad_library {

    API for spreadsheets
    @creation-date 25 August 2010
    @cs-id $Id:
}


# orientation defaults to RC (row column reference and format, where rows within a column are the same data type)
# for CR orientation, switch the references so a column ref is a row reference and a row ref is a column ref.
# this could get confusing...  
# All internal should orient at RC to handle column titles. 
# If CR orientation, just display by switching axis
# user input would then be converted before passing to procs.

namespace eval spreadsheet {}

# qss_tid_from_name 
# qss_tid_scalars_to_array 
# qss_tid_columns_to_array_of_lists 
# qss_table_create  
# qss_table_stats  
# qss_tables  
# qss_table_read  
# qss_table_write 
# qss_table_delete 
# qss_table_trash 

# spreadsheet::read_as_lists <-- equivalent to qss_table_read
# spreadsheet::read <--> qss_tids_columns_to_array_of_lists

#    set spreadsheet_id [db_nextval qss_id_seq]


ad_proc -public spreadsheet::id_from_name {
    sheet_name
    {instance_id ""}
    {user_id ""}
} {
    Returns the sheet_id (sid) of the most recent sheet_id of sheet name. If the sheet name contains a search glob, returns the newest id of the name matching the glob.
} {
    if { $instance_id eq "" } {
        # set instance_id package_id
        set instance_id [ad_conn package_id]
    }
    if { $user_id eq "" } {
        set user_id [ad_conn user_id]
        set untrusted_user_id [ad_conn untrusted_user_id]
    }
    # check permissions
    set read_p [permission::permission_p -party_id $user_id -object_id $instance_id -privilege read]
    set return_id ""

    if { $read_p } {
        if { [regexp -- {[\?\*]} $sheet_name ] } {
            regsub -nocase -all -- {[^a-z0-9_\?\*]} $sheet_name {_} sheet_name

            set return_list_of_lists [db_list_of_lists spreadsheet_stats_sby_lm_1 { select id, name, last_modified from qss_sheets where ( trashed is null or trashed = '0' ) and instance_id = :instance_id order by last_modified} ] 
            # create a list of names
            #ns_log Notice "spreadsheet::id_from_name.33: sheet_name '$sheet_name' return_list_of_lists $return_list_of_lists"
            set names_list [list ]
            foreach lol $return_list_of_lists {
                lappend names_list [lindex $lol 1]
            }
            # find most recent matching name
            set id_idx [lsearch -nocase $return_list $sheet_name]
            #ns_log Notice "spreadsheet::id_from_name.40: id_idx $id_idx"
            if { [llength $id_idx_list ] > 0 } {
                # set idx to first matching. 
                set return_id [lindex [lindex $return_list_of_lists $id_idx] 0]
            }
        } else {
            # no glob in sheet_name
            set return_id [db_string spreadsheet_stats_id_read { select id, last_modified from qss_sheets where name =:sheet_name and ( trashed is null or trashed = '0' ) and instance_id = :instance_id order by last_modified desc limit 1 } -default "" ] 
            #ns_log Notice "spreadsheet::id_from_name.48: sheet_name '$sheet_name' return_id '$return_id'"
        }
    }
    return $return_id
}


ad_proc -public spreadsheet::xref_1row {
    id 
    array_name
    {row_nbr "1"}
    {scalars_unfiltered ""}
    {scalars_required ""}
    {instance_id ""}
    {user_id ""}
} {
    Similar to spreadsheet::read except that since there's only 1 row, values are not wrapped in a list.

    Saves scalars in a 2 row table to an array array_name, 
    where array indexes are the scalars in the row 0 'name' column, and 
    the value for each scalar is row 1 in column. 
    id is a reference to a qss_sheets table. 
    Also, returns the name/value pairs in a list. 
    If any scalars_required are not included, 
    includes these indexes and sets values to empty string.
} {
    upvar $array_name id_arr

    if { $scalars_unfiltered ne "" && [llength $scalars_unfiltered] == 1 } {
        set scalars_unfiltered [split $scalars_unfiltered]
    }
    if { $scalars_required ne "" && [llength $scalars_required] == 1 } {
        set scalars_required [split $scalars_required]
    }
    set names_values_list [list ]
    # load table_id
    set id_lists [spreadsheet::read_as_lists $id $instance_id $user_id]
    # extract each name-value pair, saving into array
    set titles_list [lindex $id_lists 0]
    set index 0
    foreach title $titles_list {
        if { [regexp -nocase -- {name[s]?} $title] } {
            set name_idx $index
        }
        if { [regexp -nocase -- {value[s]?} $title] } {
            set value_idx $index
        }
        incr index
    }
    if { [info exists value_idx] && [info exists name_idx] } {
        foreach row_list [lrange $id_lists 1 end] {
            set name [lindex $row_list $name_idx]
            set value [lindex $row_list $value_idx]
            regsub -nocase -all -- {[^a-z0-9_]+} $name {_} name
            set scalar_idx [lsearch $scalars_unfiltered $name]
            if { $name ne "" && $scalar_idx > -1 } {
                lappend names_values_list $name $value
                set scalars_unfiltered [lreplace $scalars_unfiltered $scalar_idx $scalar_idx]
                set scalar_idx [lsearch $scalars_required $name]
                if { $scalar_idx > -1 } {
                    set scalars_required [lreplace $scalars_required $scalar_idx $scalar_idx]
                }
                set id_arr($name) $value
            }
        }
        # create blank defaults for missing, required name/value pairs.
        foreach scalar $scalars_required {
            set id_arr($scalar) ""
            lappend names_values_list $scalar ""
        }
    } 
    return $names_values_list
}


ad_proc -public spreadsheet::create.old { 
    id
    name_abbrev
    sheet_title
    style_ref
    sheet_description
    {orientation "RC"}
} {
    creates spreadsheet
} {
    # if id exists, assume it's a double click or bad info, ignore
    set success 0
    if { [spreadsheet::status_q $id] eq "" } {
        set package_id [ad_conn package_id]
        set user_id [ad_conn user_id]
        set create_p [permission::permission_p -party_id $user_id -object_id $package_id -privilege create]
        if { $create_p } { 
            db_dml create_new_sheet {insert into qss_sheets 
           (id, instance_id, name_abbrev, style_ref, sheet_description, orientation,row_count,column_count,last_calclated,last_modified, last_modified_by) 
            values (:id, :package_id, :name_abbrev, :style_ref, :sheet_description, :orientation, '0', '0', now(), now(), :user_id ) }
        }
        set success $create_p
    } 
    return $success
}

ad_proc -public spreadsheet::create { 
    array_name
    name
    title
    comments
    {template_id ""}
    {flags ""}
    {instance_id ""}
    {user_id ""}
} {
    Creates spreadsheet. returns id, or 0 if error. instance_id is usually package_id
} {

#code.  Be sure to check permissions

#   CREATE TABLE qss_sheets (
#       id integer not null primary key,
#       template_id integer,
#       instance_id integer,
#       user_id integer,
#       flags varchar(12),
#       name varchar(40),
#       style_ref varchar(300),
#       title varchar(80),
#       description text,
#       orientation varchar(2) default 'RC',
#       row_count integer,
#       cell_count integer,
#       trashed varchar(1) default '0',
#       popularity integer,
#       last_calculated timestamptz,
#       last_modified timestamptz,
#       last_modified_by integer,
#       status varchar(8)
#   );
#   CREATE TABLE qss_cells (
#       id integer not null primary key,
#       sheet_id integer not null,
#       cell_row integer not null,
#       cell_column integer not null,
#       cell_name varchar(40),
#       cell_value varchar(1025),
#       cell_type varchar(8),
#       cell_format varchar(80),
#       cell_proc varchar(1025),
#       cell_calc_depth integer not null default '0',
#       cell_title varchar(80),
#       last_calculated timestamptz,
#       last_modified timestamptz,
#       last_modified_by integer
#   );

    if { $instance_id eq "" } {
        # set instance_id package_id
        set instance_id [ad_conn package_id]
    }
    if { $user_id eq "" } {
        set user_id [ad_conn user_id]
        set untrusted_user_id [ad_conn untrusted_user_id]
    }
    set create_p [permission::permission_p -party_id $user_id -object_id $instance_id -privilege create]
    ns_log Notice "spreadsheet::create: create_p $create_p with raw rows cells_list_of_lists [llength $cells_list_of_lists]"
    if { $create_p } {
        set id [db_nextval qss_id_seq]
        ns_log Notice "spreadsheet::create: new id $id"
        set sheet_exists_p [db_0or1row sheet_get_id {select name from qss_sheets where id = :id } ]
        if { !$sheet_exists_p } {
            if { $template_id eq "" } {
                set template_id $id
            }
            set nowts [dt_systime -gmt 1]
            db_transaction {
                db_dml sheet_create { insert into qss_sheets
                    (id,template_id,name,title,comments,instance_id,user_id,flags,last_modified,created)
                    values (:id,:template_id,:name,:title,:comments,:instance_id,:user_id,:flags,:nowts,:nowts) }
                set row 0
                set cells 0
                foreach row_list $cells_list_of_lists {
                    incr row
                    set column 0
                    foreach cell_value $row_list {
                        incr column
                        incr cells
                        set cell_rc "r[string range "0000" 0 [expr { 3 - [string length $row] } ] ]${row}c[string range "0000" 0 [expr { 3 - [string length $column] } ] ]${column}"
                        # if cell_value has length of zero, then don't insert
                        if { [string length $cell_value] > 0 } {
#ns_log Notice "spreadsheet::create: cell_rc $cell_rc cell_value $cell_value"
                            db_dml qss_simple_cells_create { insert into qss_simple_cells
                                (id,cell_rc,cell_value)
                                values (:id,:cell_rc,:cell_value)
                            }
                        }
                    }
                }
ns_log Notice "spreadsheet::create: total $row rows, $cells cells"
                db_dml sheet_update_rc { update qss_sheets
                    set row_count =:row,cell_count =:cells, last_modified=:nowts
                    where id = :id }

            } on_error {
                set id 0
                ns_log Error "spreadsheet::create: general psql error during db_dml"
            }
        } else {
            set id 0
            ns_log Warning "spreadsheet::create: sheet already exists for id $id"
        }
    }
    return $id
}



ad_proc -public spreadsheet::list.old { 
    package_id
    {user_id "0"}
} {
    returns list of lists of existing sheets: {id name_abbrev sheet_title last_modified by_user} 
    If user_id is passed, results are sheets that the user has created or modified within package_id.
} {
    if { $user_id eq 0 } {
        set table [db_list_of_lists get_list_of_spreadsheets {select id, name_abbrev, sheet_title, last_modified, by_user from qss_sheets where instance_id = :package_id order by sheet_title } ]
    } else {
        set table [db_list_of_lists get_list_of_spreadsheets_for_user_id {select id, name_abbrev, sheet_title, last_modified, by_user
            from qss_sheets where ( instance_id = :package_id and user_id = :user_id ) or instance_id in 
              ( select instance_id from qss_cells where sheet_id in ( select id from qss_sheets where instance_id = :package_id unique ) and last_modified_by = :user_id ) order by sheet_title } ]
    } 
}

ad_proc -public spreadsheet::stats { 
    id
    {instance_id ""}
    {user_id ""}
} {
    Returns table stats as a list: name, title, comments, cell_count, row_count, template_id, flags, trashed, popularity, time last_modified, time created, user_id.
    Columns not listed, as those might vary.
} {
    if { $instance_id eq "" } {
        # set instance_id package_id
        set instance_id [ad_conn package_id]
    }
    if { $user_id eq "" } {
        set user_id [ad_conn user_id]
        set untrusted_user_id [ad_conn untrusted_user_id]
    }
    # check permissions
    set read_p [permission::permission_p -party_id $user_id -object_id $instance_id -privilege read]

    if { $read_p } {
        set return_list_of_lists [db_list_of_lists qss_sheet_stats_read { select name, title, comments, cell_count, row_count, template_id, flags, trashed, popularity, last_modified, created, user_id from qss_sheets where id = :table_id and instance_id = :instance_id } ] 
        # convert return_lists_of_lists to return_list
        set return_list [lindex $return_list_of_lists 0]
        if { [lindex $return_list 7 ] eq "" } {
            set return_list [lreplace $return_list 7 7 "0"]
        }
    } else {
        set return_list [list ]
    }
    return $return_list
}


ad_proc -public spreadsheet::attributes.old { 
    sheet_id
} {
    returns attributes of a sheet in list format: {id name_abbrev sheet_title last_modified by_user orientation row_count column_count last_calculated last_modified sheet_status} 
} {
    set package_id [ad_conn package_id]
    set user_id [ad_conn user_id]
    set read_p [permission::permission_p -party_id $user_id -object_id $package_id -privilege read]
    if { $read_p && [spreadsheet::exists_for_rwd_q $sheet_id $package_id] } {
        set sheet_list [db_list get_spreadsheet_attributes {select id, name_abbrev, sheet_title, last_modified, by_user, orientation, row_count, column_count, last_calculated, last_modified, sheet_status from qss_sheets where instance_id = :package_id and id = :sheet_id } ]
    } else {
        set sheet_list [list ]
    }
}

ad_proc -public spreadsheet::ids{ 
    {instance_id ""}
    {user_id ""}
    {template_id ""}
} {
    Returns a list of table_ids available. If table_id is included, the results are scoped to tables with same template. If user_id is included, the results are scoped to the user.
} {
    if { $instance_id eq "" } {
        # set instance_id package_id
        set instance_id [ad_conn package_id]
    }
    if { $user_id eq "" } {
        set party_id [ad_conn user_id]
        set untrusted_user_id [ad_conn untrusted_user_id]
    } else {
        set party_id $user_id
    }
    set read_p [permission::permission_p -party_id $party_id -object_id $instance_id -privilege read]

    if { $read_p } {
        if { $template_id eq "" } {
            if { $user_id ne "" } {
                set return_list [db_list spreadsheets_user_list { select id from qss_sheets where instance_id = :instance_id and user_id = :user_id } ]
            } else {
                set return_list [db_list spreadsheets_list { select id from qss_sheets where instance_id = :instance_id } ]
            }
        } else {
            set has_template [db_0or1row spreadsheet_template "select template_id as db_template_id from qss_sheets where template_id= :template_id"]
            if { $has_template && [info exists db_template_id] && $template_id > 0 } {
                if { $user_id ne "" } {
                    set return_list [db_list spreadsheets_t_u_list { select id from qss_sheets where instance_id = :instance_id and user_id = :user_id and template_id = :template_id } ]
                } else {
                    set return_list [db_list spreadsheets_list { select id from qss_sheets where instance_id = :instance_id and template_id = :template_id } ]
                }
            } else {
                set return_list [list ]
            }
        }
    } else {
        set return_list [list ]
    }
    return $return_list
} 

ad_proc -public spreadsheet::read { 
    id
    {instance_id ""}
    {user_id ""}
    
} {
    Reads spreadsheet with id. Returns sheet as list_of_lists of cells.
} {
    if { $instance_id eq "" } {
        # set instance_id package_id
        set instance_id [ad_conn package_id]
    }
    if { $user_id eq "" } {
        set user_id [ad_conn user_id]
        set untrusted_user_id [ad_conn untrusted_user_id]
    }
    set read_p [permission::permission_p -party_id $user_id -object_id $instance_id -privilege read]
    set cells_list_of_lists [list ]
    if { $read_p } {

        set cells_data_lists [db_list_of_lists qss_sheet_read_cells { select cell_rc, cell_value from qss_simple_cells
            where table_id =:table_id order by cell_rc } ]
        set cells2_data_lists [list ]
        set col_ref_list [list ]
        # filter row, column references
        foreach cell_list $cells_data_lists {
            set cell_rc [lindex $cell_list 0]
            set cell_value [lindex $cell_list 1]

            # following based on "0000" format used in create/write cell_rc r0001c0001
            set row [string range $cell_rc 1 4]
            regsub {^[0]+} $row {} row
            set column [string range $cell_rc 6 9]
            regsub {^[0]+} $column {} column
            set row_list [list $row $column $cell_value]
            lappend cells2_data_lists $row_list
            lappend col_ref_list $column
        }
        # determine max referenced column
        set column_max [f::lmax $col_ref_list]

        set prev_row 1
        set row_list [list ]
        foreach cell_list $cells2_data_lists {
            set row [lindex $cell_list 0]
            set column [lindex $cell_list 1]
            set cell_value [lindex $cell_list 2]
#            ns_log Notice "spreadsheet::read: cell ${cell_rc} ($row,$column) value ${cell_value}"     

            # build row list
            if { $row eq $prev_row } {
                # add cell to same row.  column_next is column to fill as represented by cell column number 1...n
                set column_next [expr { [llength $row_list ] + 1 } ]
                set cols_to_add [expr { $column - $column_next } ]
                
                # add blank cells, if needed
                for {set i 0} {$i < $cols_to_add} {incr i } {
                    lappend row_list ""
                }
                lappend row_list $cell_value
            } else {
                # check for any blank orphan cells to add
                set column_next [expr { [llength $row_list ] + 1 } ]
                set cols_to_add [expr { $column_max - $column_next + 1 } ]

                # add blank cells, if needed
                for {set i 0} {$i < $cols_to_add} {incr i } {
                    lappend row_list ""
                }

                # row finished, add row_list to cells_list_of_lists
                lappend cells_list_of_lists $row_list

                # start new row
                set row_list [list ]
                set column_next [expr { [llength $row_list ] + 1 } ]
                set cols_to_add [expr { $column - $column_next } ]

                # add blank cells, if needed
                for {set i 0} {$i < $cols_to_add} {incr i } {
                    lappend row_list ""
                }
                lappend row_list $cell_value
            }
            set prev_row $row
        }

        # check for any blank orphan cells at end of row that need adding
        set column_next [expr { [llength $row_list ] + 1 } ]
        set cols_to_add [expr { $column_max - $column_next + 1 } ]
        # add blank cells, if needed
        for {set i 0} {$i < $cols_to_add} {incr i } {
            lappend row_list ""
        }
        lappend cells_list_of_lists $row_list
    }
    return $cells_list_of_lists
}

ad_proc -public spreadsheet::cells_read.old { 
    sheet_id
    {start ""}
    {count ""}
} {
    reads spreadsheet, returns list_of_lists, each cell is an element in the list
    If orientation is RC, cells are sorted first by row.
    If orientation is CR, cells are sorted first by column.
    first element contains header references
} {
    if { [ad_var_type_check_number_p $start] && $start > 0 && [ad_var_type_check_number_p $count] && $count > 0 } {
        set page_start $start
        set page_size $count
    }
    set package_id [ad_conn package_id]
    set user_id [ad_conn user_id]
    set read_p [permission::permission_p -party_id $user_id -object_id $package_id -privilege read]
    # if orientation is RC, start is start_row, count is num_of_rows
    # if orientation is CR, start is start_col, count is num_of_columns
    if { $read_p && [spreadsheet::exists_for_rwd_q $sheet_id $package_id] } {
        if { [info exists $page_start] } {
            set table [db_list_of_lists get_all_cells_of_sheet {select id, cell_row, cell_column, cell_value, cell_value_sq, cell_format, cell_proc, cell_calc_depth, cell_name, cell_title from qss_cells where sheet_id = :sheet_id} limit :page_size offest :page_start ]
        } else {
            set table [db_list_of_lists get_all_cells_of_sheet {select id, cell_row, cell_column, cell_value, cell_value_sq, cell_format, cell_proc, cell_calc_depth, cell_name, cell_title from qss_cells where sheet_id = :sheet_id} ]
        }
    } else {
        set table [list ]
    }        
    set table [linsert $table 0 [list id cell_row cell_column cell_value cell_value_sq cell_format cell_proc cell_calc_depth cell_name cell_title]
    return $table
}

ad_proc -public spreadsheet::cells_write {
    sheet_id
    list_of_lists
} {
    writes spreadsheet cells. 
    assumes first element of list is a list of header references to columns (if orientatin is RC) or rows (if CR).
    if row or column reference is not provided, appends new lines.
    Reserved header references (attribute) have features automatically attached to them:
    cell_row (positive integer) if RC orientation, replaces an existing cell_row if it exists.
    cell_column (positive integer) if CR orientation, replaces an existing cell_column if it exists.
    id (positive integer) replaces existing id if it exists.
    other attrributes: cell_format cell_proc cell_name cell_title
} {
    set success 0
    set package_id [ad_conn package_id]
    set user_id [ad_conn user_id]
    set write_p [permission::permission_p -party_id $user_id -object_id $package_id -privilege write]
    if { $write_p && [spreadsheet::exists_for_rwd_q $sheet_id $package_id] } {
        # collect allowed attributes from first element
        set attributes_list [list id cell_row cell_column cell_value cell_format cell_proc cell_name cell_title]
        set maybe_attributes_list [lindex $list_of_lists 0]
        set attributes_passed_list [list ]
        foreach attribute_test $maybe_attributes_list {
            set attribute_index [lsearch -exact $attributes_list $attribute_test]
            if { $attribute_index > 0 } {
                set attribute_arr($attribute_test) $attribute_index
                lappend attributes_passed_list $attribute_test
            }
        }
        
        # separate cells attributes from attribute headers
        set cells_list [lreplace $list_of_lists 0 0]
        set id_exists_p [expr { [lsearch -exact $attributes_passed_list id] > 0 } ]
        # loop that grabs a cell
        foreach cell_attributes_input_list $cells_list {
            # if id exists, use that reference over cell_row or cell_column
            # make sure the id is bound to this spreadsheet, or it could overwrite parts of other spreadsheets.

            # loop that assigns cell attributes
            set mode ""
            set attributes_to_write_list [list ]
            set att_values_to_write_list [list ]
            set sql_separator ""
            # set the following, because they are referenced to find id, and may not be in attributes_passed_list
            set cell_row ""
            set cell_column ""
            set cell_name ""
            set cell_title ""
            foreach attribute_to_write $attributes_passed_list {
                set ${attribute_to_write} [lindex $cell_attributes_input_list $attribute_arr($attribute_to_write)]
                if { $attribute_to_write eq "id" && $mode eq "" } {
                    set mode id
                    # cell_id
                    set id $attr_value(id)
                }  elseif { } {
                    lappend attributes_to_write_list $attribute_to_write
                    lappend att_values_to_write_list $attr_value(${attribute_to_write})
                    append update_text "${sql_separator}${attributed_to_write}=:${attribute_to_write}"
                    set sql_separator ","
                }
            }
            if { $mode ne "id" } {
                #  is there an implied id?
                if { [set id [spreadsheet::cell_id_from_other $sheet_id $package_id "" $cell_row $cell_column $cell_name $cell_title] ] ne "" } {
                    set mode id
                }
            }
            #  write cell attributes

            if { $mode eq "id" } {
                if { [spreadsheet::id_from_cell_id $id] == $sheet_id } {
                    db_dml update_cell_attributes {update qss_cells set :update_text where id = :id}
                } else {
                    set id [spreadsheet::new_id]
                    set attributes_to_write_db [template::util::tcl_to_sql_list $attributes_to_write_list]
                    set att_values_to_write_db [template::util::tcl_to_sql_list $att_values_to_write_list]
                    db_dml insert_spreadsheet_cell {insert into qss_cells ( id, :attributes_to_write_db) values ( :id, :att_values_write_db) }
                }
            } else {
                # we don't know any other mode right now. Log it.
                ns_log Warning "spreadsheet::cells_write: mode is not 'id' for sheet_id ${sheet_id}, where update_text = ${update_text}"
            }
        }
    }
    return $success
}

ad_proc -public spreadsheet::delete {
    spreadsheet_id
} {
    deletes spreadsheet
} {
   # validate permission, and confirm its existence
    set package_id [ad_conn package_id]
    set user_id [ad_conn user_id]
    set delete_p [permission::permission_p -party_id $user_id -object_id $package_id -privilege delete]
    if { $delete_p } {
        # delete references in qss_cells
        db_1row {spreadsheet_cell_count "select rows(*) as row_count from qss_cells where sheet_id = :spreadsheet_id and instance_id = :package_id"}
        if { $row_count > 0 } {
            db_dml spreadsheet_cells_delete_all "delete from qss_cells where sheet_id = :spreadsheet_id  and instance_id = :package_id"
        }
        # delete reference in qss_sheets
        db_1row {spreadsheet_cell_count "select rows(*) as sheet_exists_q from qss_cells where id = :spreadsheet_id and instance_id = :package_id"}
        if { $sheet_exists_q } {
            db_dml  spreadsheet_delete "delete from qss_sheets where id = :spreadsheet_id  and instance_id = :package_id"
        }
        set success 1
    } else {
        set success 0
    }
    return $success
} 

ad_proc -public spreadsheet::list {
} {
    returns list_of_lists of available spreadsheets
    each list item contains:
    id, name_abbrev, sheet_title,row_count,column_count,last_calculated,last_modified,status
} {

}

ad_proc -private spreadsheet::status_q { 
    sheet_id
} {
    gets spreadsheet status
} {
    db_0or1row get_spreadsheet_status "select sheet_status from qss_sheets where id = :sheet_id"
    if { ![info exists sheet_status] } {
        set sheet_status ""
    }
    return $sheet_status
}
