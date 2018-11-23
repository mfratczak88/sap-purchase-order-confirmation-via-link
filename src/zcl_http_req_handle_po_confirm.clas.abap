class ZCL_HTTP_REQ_HANDLE_PO_CONFIRM definition
  public
  create public .

public section.

  interfaces IF_HTTP_EXTENSION .
protected section.
private section.

  data MO_REST_REQUEST type ref to IF_REST_REQUEST .
  data MO_REST_RESPONSE type ref to IF_REST_RESPONSE .
  constants MC_RESOURCE_CLASS type SEOCLASS value 'ZCL_REST_PO_CONFIRMATION' ##NO_TEXT.
  constants MC_URI_CONFIRMATION_PATTERN type STRING value '/confirm/{guid}' ##NO_TEXT.
  data MO_SERVER type ref to IF_HTTP_SERVER .
  data MO_HANDLER type ref to IF_REST_HANDLER .
  data MC_OK_HTML type STRING value '<html><body><p>Zamówienie potwierdzone</p></body></html>' ##NO_TEXT.
  data MC_ERROR_HTML type STRING value '<html><body><p>Potwierdzenie nie udało się, skontaktuj się z zamawiającym</p></body></html>' ##NO_TEXT.

  methods SET_REST_HANDLER .
  methods SET_REST_REQUEST .
  methods SET_REST_RESPONSE .
  methods SET_SERVER
    importing
      !IO_SERVER type ref to IF_HTTP_SERVER .
  methods DISPATCH .
  methods RESPOND .
ENDCLASS.



CLASS ZCL_HTTP_REQ_HANDLE_PO_CONFIRM IMPLEMENTATION.


  METHOD dispatch.
    TRY.
        mo_handler->handle(
         EXPORTING
           io_request  = mo_rest_request
           io_response = mo_rest_response
       ).
      CATCH cx_root.
        mo_rest_response->set_status( cl_rest_status_code=>gc_client_error_forbidden ).
    ENDTRY.
  ENDMETHOD.


  METHOD if_http_extension~handle_request.
*    purposedly creating rest resource as well as request and response,
*    so we can easily get URI attributes, not reinventing the wheel...

    set_server( server ).
    set_rest_handler( ).
    set_rest_request( ).
    set_rest_response( ).

    dispatch( ).

    respond( ).

  ENDMETHOD.


  METHOD respond.
    IF mo_rest_response->get_status( ) = cl_rest_status_code=>gc_success_ok.
      mo_server->response->set_cdata( mc_ok_html ).
    ELSE.
      mo_server->response->set_cdata( mc_error_html ).
    ENDIF.
  ENDMETHOD.


  METHOD set_rest_handler.
    DATA: lo_http_request     TYPE REF TO if_http_request,
          lo_rest_base_entity TYPE REF TO cl_rest_base_entity,
          lo_router           TYPE REF TO cl_rest_router,
          lo_rest_handler     TYPE REF TO if_rest_handler.
    TRY.
        lo_router = NEW #( ).
        lo_router->attach(
          EXPORTING
            iv_template      =  mc_uri_confirmation_pattern  " Unified Name for Resources
            iv_handler_class =  CONV #( mc_resource_class )    " Object Type Name
        ).

        mo_handler ?= lo_router.
      CATCH cx_root.
    ENDTRY.
  ENDMETHOD.


  method SET_REST_REQUEST.
    mo_rest_request  = cl_rest_message_builder=>create_http_request( mo_server->request ).
  endmethod.


  method SET_REST_RESPONSE.
    mo_rest_response = cl_rest_message_builder=>create_http_response( mo_server->response ).
  endmethod.


  method SET_SERVER.
    mo_server = io_server.
  endmethod.
ENDCLASS.
