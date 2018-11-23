class ZCL_REST_PO_CONFIRMATION definition
  public
  inheriting from CL_REST_RESOURCE
  final
  create public .

public section.

  methods IF_REST_RESOURCE~GET
    redefinition .
  methods IF_REST_RESOURCE~POST
    redefinition .
protected section.
private section.

  data MV_HEADER type EBELN .
  data MV_ITEM type EBELP .
  data MO_PO type ref to CL_PO_HEADER_HANDLE_MM .
  data MO_PO_ITEM type ref to CL_PO_ITEM_HANDLE_MM .
  data MC_PO_CONFIRMATION_TABLE type TABNAME16 value 'ZMM_CONFIRM_PO' ##NO_TEXT.
  data MV_GUID type GUID_32 .

  methods CONFIRM_PO
    returning
      value(APPROVED) type BOOLEAN .
  methods PREPARE_PO
    returning
      value(PREPARED) type BOOLEAN .
  methods SET_HEADER_AND_ITEM_FROM_GUID .
  methods PREPARE_PO_ITEM
    returning
      value(PREPARED) type BOOLEAN .
  methods SET_TIMESTAMP_ON_ITEM .
  methods GET_MODELS
    returning
      value(RT_MODELS) type MMPUR_MODELS .
  methods MARK_PO_AS_CONFIRMED .
  methods GET_RECORD_FROM_CONFIRM_TABLE
    returning
      value(RR_RECORD) type ref to DATA .
  methods IS_ALREADY_CONFIRMED
    returning
      value(CONFIRMED) type BOOLEAN .
  methods SET_OK_RESPONSE .
  methods SET_ERROR_RESPONSE .
ENDCLASS.



CLASS ZCL_REST_PO_CONFIRMATION IMPLEMENTATION.


  METHOD CONFIRM_PO.
    DATA: lt_models TYPE mmpur_models.

    approved = abap_false. "default.

    CHECK prepare_po( ) = abap_true.
    CHECK prepare_po_item( ) = abap_true.

    set_timestamp_on_item( ).

    lt_models = get_models( ).
    CHECK lt_models IS NOT INITIAL.

    mo_po->if_flush_transport_mm~start(
      EXPORTING
        im_models    = lt_models
    ).
    CHECK sy-subrc = 0.

    mo_po->po_post(
      EXPORTING
        im_uncomplete     = mmpur_no    " Incomplete
        im_no_commit      = mmpur_no    " No Commit
        im_commit_wait    = mmpur_yes   " Commit and Wait
    ).
    CHECK sy-subrc = 0.

    approved = abap_true.
  ENDMETHOD.


  METHOD get_models.
    DATA: ls_model LIKE LINE OF rt_models.

    TRY.
        ls_model-model ?= mo_po_item.
      CATCH cx_sy_move_cast_error.
        RETURN.
    ENDTRY.

    APPEND ls_model TO rt_models.
  ENDMETHOD.


  METHOD get_record_from_confirm_table.
    DATA: lo_structdescr     TYPE REF TO cl_abap_structdescr.

    " all the hassle below is to have the actual name of table in the class constant and not hardcoded.
    TRY.
        lo_structdescr ?= cl_abap_typedescr=>describe_by_name( mc_po_confirmation_table ).
        CREATE DATA rr_record TYPE HANDLE lo_structdescr.
      CATCH cx_root.
        RETURN.
    ENDTRY.

    ASSIGN rr_record->* TO FIELD-SYMBOL(<fs_confirmation_po>).
    CHECK <fs_confirmation_po> IS ASSIGNED.

    SELECT SINGLE *
      FROM (mc_po_confirmation_table)
      INTO <fs_confirmation_po>
      WHERE guid = mv_guid.

  ENDMETHOD.


  METHOD if_rest_resource~get.
    DATA: confirmed TYPE boolean.
    mv_guid = CONV #( mo_request->get_uri_attribute( 'guid' ) ).

    " if its already confirm, set ok.
    confirmed = is_already_confirmed( ).
    IF confirmed = abap_true.
      set_ok_response( ).
      RETURN.
    ENDIF.

    " confirm if not already
    set_header_and_item_from_guid( ).
    confirmed = confirm_po( ).

    " set reponse
    IF confirmed = abap_true.
      mark_po_as_confirmed( ).
      set_ok_response( ).
    ELSE.
      set_error_response( ).
    ENDIF.
  ENDMETHOD.


  method IF_REST_RESOURCE~POST.
*CALL METHOD SUPER->IF_REST_RESOURCE~POST
*  EXPORTING
*    IO_ENTITY =
*    .
  endmethod.


  METHOD is_already_confirmed.
    data: lr_record type ref to data.

    lr_record = get_record_from_confirm_table( ).
    ASSIGN lr_record->* TO FIELD-SYMBOL(<fs_record>).

    ASSIGN COMPONENT 'CONFIRMED' OF STRUCTURE <fs_record> TO FIELD-SYMBOL(<confirmed>).
    CHECK <confirmed> IS ASSIGNED.

    confirmed = <confirmed>.
  ENDMETHOD.


  METHOD mark_po_as_confirmed.
    DATA: lr_record TYPE REF TO data.

    lr_record = get_record_from_confirm_table( ).
    ASSIGN lr_record->* TO FIELD-SYMBOL(<fs_record>).

    ASSIGN COMPONENT 'CONFIRMED' OF STRUCTURE <fs_record> TO FIELD-SYMBOL(<confirmed>).
    CHECK <confirmed> IS ASSIGNED.
    <confirmed> = abap_true.

    TRY.
        MODIFY (mc_po_confirmation_table) FROM <fs_record>.
      CATCH cx_root.
    ENDTRY.
  ENDMETHOD.


  METHOD prepare_po.
    TYPE-POOLS: abap, mmpur.
    DATA : ls_document   TYPE mepo_document,
           ls_mepoheader TYPE mepoheader.

    " init
    prepared = abap_false.

    ls_document-process = mmpur_po_process.
    ls_document-trtyp = 'V'.
    ls_document-initiator-initiator = mmpur_initiator_call.
    MOVE mv_header TO ls_document-doc_key(10).

    mo_po = NEW #( mv_header ).
    CHECK mo_po IS BOUND AND sy-subrc = 0.

    mo_po->set_state( im_state = cl_po_header_handle_mm=>c_available ).
    mo_po->for_bapi = mmpur_yes.

    mo_po->po_initialize( im_document = ls_document ).
    mo_po->po_read(
      EXPORTING
          im_tcode     = 'ME22N'
           im_trtyp     = ls_document-trtyp
           im_aktyp     = ls_document-trtyp
           im_po_number = mv_header
           im_document  = ls_document
         IMPORTING
           ex_result    = prepared
    ).
  ENDMETHOD.


  METHOD prepare_po_item.
    prepared = abap_false. " default.

    DATA(lt_items) = mo_po->if_purchase_order_mm~get_items( ).

    CHECK lines( lt_items ) > 0.

    LOOP AT lt_items ASSIGNING FIELD-SYMBOL(<fs_item>).
      IF <fs_item>-item->get_data( )-ebelp = mv_item.
        DATA(lo_item) = <fs_item>-item.
        EXIT.
      ENDIF.
    ENDLOOP.

    CHECK lo_item IS BOUND.
    TRY.
        mo_po_item ?= lo_item.
        prepared = abap_true.
      CATCH cx_root.
        " pointless adding here anything
        " because return value if any errors,
        " would not be changed to true anyway.
    ENDTRY.
  ENDMETHOD.


  method SET_ERROR_RESPONSE.
    mo_response->set_status( cl_rest_status_code=>gc_server_error_internal ).
  endmethod.


  METHOD set_header_and_item_from_guid.
    DATA: lo_structdescr     TYPE REF TO cl_abap_structdescr,
          lr_confirmation_po TYPE REF TO data.

    lr_confirmation_po = get_record_from_confirm_table( ).
    CHECK lr_confirmation_po IS BOUND.

    ASSIGN lr_confirmation_po->* TO FIELD-SYMBOL(<fs_confirmation_po>).
    CHECK <fs_confirmation_po> IS ASSIGNED.

    ASSIGN COMPONENT 'EBELN' OF STRUCTURE <fs_confirmation_po> TO FIELD-SYMBOL(<header>).
    ASSIGN COMPONENT 'EBELP' OF STRUCTURE <fs_confirmation_po> TO FIELD-SYMBOL(<item>).

    CHECK <header> IS ASSIGNED AND <item> IS ASSIGNED.

    mv_header = <header>.
    mv_item =  <item>.

  ENDMETHOD.


  method SET_OK_RESPONSE.
    mo_response->set_status( cl_rest_status_code=>gc_success_ok ) .
  endmethod.


  METHOD set_timestamp_on_item.

    mo_po_item->get_data(
      IMPORTING
        ex_data =  DATA(ls_item_data)   " Data Part
    ).

    DATA(time_stamp) = | { sy-datum } / { sy-uzeit } |.
    MOVE time_stamp TO ls_item_data-labnr.

    mo_po_item->set_data( ls_item_data ).
  ENDMETHOD.
ENDCLASS.
