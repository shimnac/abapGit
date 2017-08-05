*&---------------------------------------------------------------------*
*&  Include           ZABAPGIT_TADIR
*&---------------------------------------------------------------------*

*----------------------------------------------------------------------*
*       CLASS lcl_tadir DEFINITION
*----------------------------------------------------------------------*
*
*----------------------------------------------------------------------*
CLASS lcl_tadir DEFINITION FINAL.

  PUBLIC SECTION.
    CLASS-METHODS:
      read
        IMPORTING iv_package            TYPE tadir-devclass
                  iv_ignore_subpackages TYPE abap_bool DEFAULT abap_false
                  io_dot                TYPE REF TO lcl_dot_abapgit OPTIONAL
        RETURNING VALUE(rt_tadir)       TYPE lif_defs=>ty_tadir_tt
        RAISING   lcx_exception,
      read_single
        IMPORTING iv_pgmid        TYPE tadir-pgmid DEFAULT 'R3TR'
                  iv_object       TYPE tadir-object
                  iv_obj_name     TYPE tadir-obj_name
        RETURNING VALUE(rs_tadir) TYPE tadir,
      read_single_sicf
        IMPORTING iv_pgmid        TYPE tadir-pgmid DEFAULT 'R3TR'
                  iv_obj_name     TYPE tadir-obj_name
        RETURNING VALUE(rs_tadir) TYPE tadir
        RAISING   lcx_exception,
      get_object_package
        IMPORTING iv_pgmid           TYPE tadir-pgmid DEFAULT 'R3TR'
                  iv_object          TYPE tadir-object
                  iv_obj_name        TYPE tadir-obj_name
        RETURNING VALUE(rv_devclass) TYPE tadir-devclass.

  PRIVATE SECTION.
    CLASS-METHODS:
      read_sicf_url
        IMPORTING iv_obj_name    TYPE tadir-obj_name
        RETURNING VALUE(rv_hash) TYPE text25
        RAISING   lcx_exception,
      check_exists
        IMPORTING it_tadir        TYPE lif_defs=>ty_tadir_tt
        RETURNING VALUE(rt_tadir) TYPE lif_defs=>ty_tadir_tt
        RAISING   lcx_exception,
      build
        IMPORTING iv_package            TYPE tadir-devclass
                  iv_top                TYPE tadir-devclass
                  io_dot                TYPE REF TO lcl_dot_abapgit
                  iv_ignore_subpackages TYPE abap_bool DEFAULT abap_false
        RETURNING VALUE(rt_tadir)       TYPE lif_defs=>ty_tadir_tt
        RAISING   lcx_exception.

ENDCLASS.                    "lcl_tadir DEFINITION

*----------------------------------------------------------------------*
*       CLASS lcl_tadir IMPLEMENTATION
*----------------------------------------------------------------------*
*
*----------------------------------------------------------------------*
CLASS lcl_tadir IMPLEMENTATION.

  METHOD read_single.

    DATA: lv_obj_name TYPE tadir-obj_name.


    IF iv_object = 'SICF'.
      rs_tadir = read_single_sicf( iv_pgmid = iv_pgmid
                                   iv_obj_name = iv_obj_name ).
    ELSE.
      SELECT SINGLE * FROM tadir INTO rs_tadir
        WHERE pgmid = iv_pgmid
        AND object = iv_object
        AND obj_name = iv_obj_name.                       "#EC CI_SUBRC
    ENDIF.

  ENDMETHOD.                    "read_single

  METHOD read_single_sicf.

    DATA: lt_tadir    TYPE STANDARD TABLE OF tadir WITH DEFAULT KEY,
          lv_hash     TYPE text25,
          lv_obj_name TYPE tadir-obj_name.

    FIELD-SYMBOLS: <ls_tadir> LIKE LINE OF lt_tadir.


    lv_hash = iv_obj_name+15.
    CONCATENATE iv_obj_name(15) '%' INTO lv_obj_name.

    SELECT * FROM tadir INTO TABLE lt_tadir
      WHERE pgmid = iv_pgmid
      AND object = 'SICF'
      AND obj_name LIKE lv_obj_name.

    LOOP AT lt_tadir ASSIGNING <ls_tadir>.
      IF read_sicf_url( <ls_tadir>-obj_name ) = lv_hash.
        rs_tadir = <ls_tadir>.
        RETURN.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.

  METHOD get_object_package.

    DATA ls_tadir TYPE tadir.

    ls_tadir = read_single( iv_pgmid    = iv_pgmid
                            iv_object   = iv_object
                            iv_obj_name = iv_obj_name ).

    IF ls_tadir-delflag = 'X'.
      RETURN. "Mark for deletion -> return nothing
    ENDIF.

    rv_devclass = ls_tadir-devclass.

  ENDMETHOD.  "get_object_package.

  METHOD read_sicf_url.

    DATA: lv_name    TYPE icfname,
          lv_url     TYPE string,
          lv_parguid TYPE icfparguid.


    lv_name    = iv_obj_name.
    lv_parguid = iv_obj_name+15.

    cl_icf_tree=>if_icf_tree~get_info_from_serv(
      EXPORTING
        icf_name          = lv_name
        icfparguid        = lv_parguid
      IMPORTING
        url               = lv_url
      EXCEPTIONS
        wrong_name        = 1
        wrong_parguid     = 2
        incorrect_service = 3
        no_authority      = 4
        OTHERS            = 5 ).
    IF sy-subrc = 0.
      rv_hash = lcl_hash=>sha1_raw( lcl_convert=>string_to_xstring_utf8( lv_url ) ).
    ENDIF.

  ENDMETHOD.

  METHOD check_exists.

    DATA: lv_exists TYPE abap_bool,
          ls_item   TYPE lif_defs=>ty_item.

    FIELD-SYMBOLS: <ls_tadir> LIKE LINE OF it_tadir.


* rows from database table TADIR are not removed for
* transportable objects until the transport is released
    LOOP AT it_tadir ASSIGNING <ls_tadir>.
      ls_item-obj_type = <ls_tadir>-object.
      ls_item-obj_name = <ls_tadir>-obj_name.

      IF lcl_objects=>is_supported( ls_item ) = abap_true.
        lv_exists = lcl_objects=>exists( ls_item ).
        IF lv_exists = abap_true.
          APPEND <ls_tadir> TO rt_tadir.
        ENDIF.
      ELSE.
        APPEND <ls_tadir> TO rt_tadir.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.                    "check_exists

  METHOD read.

* start recursion
* hmm, some problems here, should TADIR also build path?
    rt_tadir = build( iv_package            = iv_package
                      iv_top                = iv_package
                      io_dot                = io_dot
                      iv_ignore_subpackages = iv_ignore_subpackages ).

    rt_tadir = check_exists( rt_tadir ).

  ENDMETHOD.                    "read

  METHOD build.

    DATA: lt_tadir TYPE lif_defs=>ty_tadir_tt,
          lt_tdevc TYPE STANDARD TABLE OF tdevc,
          lv_path  TYPE string.

    FIELD-SYMBOLS: <ls_tdevc> LIKE LINE OF lt_tdevc,
                   <ls_tadir> LIKE LINE OF rt_tadir.


    SELECT * FROM tadir
      INTO CORRESPONDING FIELDS OF TABLE rt_tadir
      WHERE devclass = iv_package
      AND pgmid = 'R3TR'
      AND object <> 'DEVC'
      AND object <> 'SOTR'
      AND object <> 'SFB1'
      AND object <> 'SFB2'
      AND object <> 'STOB' " auto generated by core data services
      AND delflag = abap_false
      ORDER BY PRIMARY KEY.               "#EC CI_GENBUFF "#EC CI_SUBRC

    IF NOT io_dot IS INITIAL.
      lv_path = lcl_folder_logic=>package_to_path(
        iv_top     = iv_top
        io_dot     = io_dot
        iv_package = iv_package ).
    ENDIF.

    LOOP AT rt_tadir ASSIGNING <ls_tadir>.
      <ls_tadir>-path = lv_path.

      CASE <ls_tadir>-object.
        WHEN 'SICF'.
* replace the internal GUID with a hash of the path
          <ls_tadir>-obj_name+15 = read_sicf_url( <ls_tadir>-obj_name ).
      ENDCASE.
    ENDLOOP.

* look for subpackages
    IF iv_ignore_subpackages = abap_false.
      SELECT * FROM tdevc INTO TABLE lt_tdevc
        WHERE parentcl = iv_package
        ORDER BY PRIMARY KEY.             "#EC CI_SUBRC "#EC CI_GENBUFF
    ENDIF.

    LOOP AT lt_tdevc ASSIGNING <ls_tdevc>.
      lt_tadir = build( iv_package = <ls_tdevc>-devclass
                        iv_top     = iv_top
                        io_dot     = io_dot ).
      APPEND LINES OF lt_tadir TO rt_tadir.
    ENDLOOP.

  ENDMETHOD.                    "build

ENDCLASS.                    "lcl_tadir IMPLEMENTATION
