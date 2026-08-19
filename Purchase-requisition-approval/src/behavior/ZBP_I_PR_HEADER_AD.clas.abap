*&---------------------------------------------------------------------*
*& Class:   ZBP_I_PR_HEADER_AD (behavior pool)
*& Purpose: Implements the managed RAP behavior for Purchase
*&          Requisition (ZI_PR_HEADER_AD / ZI_PR_ITEM_AD), draft-enabled.
*& Target:  SAP BTP ABAP Environment / S/4HANA (ABAP Cloud)
*&
*& Note: this project uses the Local Handler Class (LHC) pattern. In
*&       Eclipse/ADT this class is physically split into two source
*&       includes:
*&         - "Global Class" tab: kept empty (see below) - it only
*&           exists to satisfy "managed implementation in class
*&           zbp_i_pr_header_ad unique;" in ZI_PR_HEADER_AD.bdef.
*&         - "Local Types" tab: contains LHC_PURCHASEREQUISITION and
*&           LHC_PURCHASEREQUISITIONITEM, one local handler class per
*&           entity, each INHERITING FROM cl_abap_behavior_handler.
*&           This file lists both includes below, in that order, with
*&           a comment marking where one ends and the other begins -
*&           paste each part into its matching tab in ADT.
*&
*& Note: this environment has a reproducible bug where a standalone
*&       "DATA x TYPE TABLE FOR UPDATE/EXECUTE <entity>." declaration
*&       inside an LHC method fails activation with "The type ... is
*&       not an entity for which BEHAVIOR can be defined" - even for a
*&       trivial, unrelated test object on a freshly provisioned
*&       system. The workaround used throughout this class: never
*&       declare that type explicitly; always build the WITH table
*&       inline as VALUE #( ... ) directly in the MODIFY ENTITIES
*&       statement (looping row-by-row instead of batching into a
*&       pre-typed table where necessary). See
*&       docs/type-table-for-update-workaround.md for the full story.
*&
*& Note: implements determinations (setRequester, setPRNumber,
*&       calculateTotal, setApprovalData on the header; setItemNumber,
*&       setItemCurrency, calculateItemAmount on the item), validations
*&       (validateAmount, validateItems, validateRejectReason), actions
*&       (submit, approve, reject, requestInfo), and instance feature
*&       control.
*& Note: pr_number is drawn from number range object ZPR_NR_AD (see
*&       src/dictionary/ZPR_NR_AD.md) - number range object names are
*&       limited to 10 characters, which is why it isn't called
*&       ZPR_RANGE_AD (12 chars, rejected at creation).
*& Note: calculateTotal's field trigger (TotalAmount) never fires on
*&       its own since TotalAmount is readonly - it is force-run via
*&       the determine action recalcTotal, invoked explicitly by
*&       calculateItemAmount for every affected parent header.
*&---------------------------------------------------------------------*

*&---------------------------------------------------------------------*
*& "Global Class" tab - keep exactly this, empty
*&---------------------------------------------------------------------*
CLASS zbp_i_pr_header_ad DEFINITION PUBLIC ABSTRACT FINAL FOR BEHAVIOR OF zi_pr_header_ad.
ENDCLASS.

CLASS zbp_i_pr_header_ad IMPLEMENTATION.
ENDCLASS.


*&---------------------------------------------------------------------*
*& "Local Types" tab - everything from here to the end of the file
*&---------------------------------------------------------------------*

CLASS lhc_purchaserequisition DEFINITION INHERITING FROM cl_abap_behavior_handler.

  PRIVATE SECTION.

    CONSTANTS:
      BEGIN OF status,
        draft    TYPE zpr_header_ad-status VALUE 'DRAFT',
        pending  TYPE zpr_header_ad-status VALUE 'PENDING',
        approved TYPE zpr_header_ad-status VALUE 'APPROVED',
        rejected TYPE zpr_header_ad-status VALUE 'REJECTED',
        info_req TYPE zpr_header_ad-status VALUE 'INFO_REQ',
      END OF status.

    METHODS get_instance_features FOR INSTANCE FEATURES
      IMPORTING keys REQUEST requested_features FOR PurchaseRequisition RESULT result.

    METHODS get_instance_authorizations FOR INSTANCE AUTHORIZATION
      IMPORTING keys REQUEST requested_authorizations FOR PurchaseRequisition RESULT result.

    METHODS setInitialStatus FOR DETERMINE ON MODIFY
      IMPORTING keys FOR PurchaseRequisition~setInitialStatus.

    METHODS setRequester FOR DETERMINE ON MODIFY
      IMPORTING keys FOR PurchaseRequisition~setRequester.

    METHODS setPRNumber FOR DETERMINE ON MODIFY
      IMPORTING keys FOR PurchaseRequisition~setPRNumber.

    METHODS calculateTotal FOR DETERMINE ON SAVE
      IMPORTING keys FOR PurchaseRequisition~calculateTotal.

    METHODS setApprovalData FOR DETERMINE ON MODIFY
      IMPORTING keys FOR PurchaseRequisition~setApprovalData.

    METHODS validateAmount FOR VALIDATE ON SAVE
      IMPORTING keys FOR PurchaseRequisition~validateAmount.

    METHODS validateItems FOR VALIDATE ON SAVE
      IMPORTING keys FOR PurchaseRequisition~validateItems.

    METHODS validateRejectReason FOR VALIDATE ON SAVE
      IMPORTING keys FOR PurchaseRequisition~validateRejectReason.

    METHODS submit FOR MODIFY
      IMPORTING keys FOR ACTION PurchaseRequisition~submit RESULT result.

    METHODS approve FOR MODIFY
      IMPORTING keys FOR ACTION PurchaseRequisition~approve RESULT result.

    METHODS reject FOR MODIFY
      IMPORTING keys FOR ACTION PurchaseRequisition~reject RESULT result.

    METHODS requestInfo FOR MODIFY
      IMPORTING keys FOR ACTION PurchaseRequisition~requestInfo RESULT result.

ENDCLASS.


CLASS lhc_purchaserequisition IMPLEMENTATION.

  METHOD get_instance_features.
    READ ENTITIES OF zi_pr_header_ad IN LOCAL MODE
      ENTITY PurchaseRequisition
        FIELDS ( Status )
        WITH CORRESPONDING #( keys )
      RESULT DATA(prs).

    result = VALUE #(
      FOR pr IN prs
      ( %tky                 = pr-%tky
        %action-submit       = COND #( WHEN pr-Status = status-draft OR pr-Status = status-info_req
                                        THEN if_abap_behv=>fc-o-enabled
                                        ELSE if_abap_behv=>fc-o-disabled )
        %action-approve      = COND #( WHEN pr-Status = status-pending
                                        THEN if_abap_behv=>fc-o-enabled
                                        ELSE if_abap_behv=>fc-o-disabled )
        %action-reject       = COND #( WHEN pr-Status = status-pending
                                        THEN if_abap_behv=>fc-o-enabled
                                        ELSE if_abap_behv=>fc-o-disabled )
        %action-requestInfo  = COND #( WHEN pr-Status = status-pending
                                        THEN if_abap_behv=>fc-o-enabled
                                        ELSE if_abap_behv=>fc-o-disabled ) ) ).
  ENDMETHOD.


  METHOD get_instance_authorizations.

    result = VALUE #(
      FOR key IN keys
      ( %tky                 = key-%tky
        %update              = if_abap_behv=>auth-allowed
        %delete              = if_abap_behv=>auth-allowed
        %action-submit       = if_abap_behv=>auth-allowed
        %action-approve      = if_abap_behv=>auth-allowed
        %action-reject       = if_abap_behv=>auth-allowed
        %action-requestInfo  = if_abap_behv=>auth-allowed ) ).
  ENDMETHOD.


  METHOD setInitialStatus.

    MODIFY ENTITIES OF zi_pr_header_ad IN LOCAL MODE
      ENTITY PurchaseRequisition
        UPDATE FIELDS ( Status )
        WITH VALUE #(
          FOR key IN keys
          ( %tky   = key-%tky
            Status = status-draft ) ).
  ENDMETHOD.


  METHOD setRequester.

    TRY.
        DATA(current_user) = cl_abap_context_info=>get_user_technical_name( ).
      CATCH cx_abap_context_info_error INTO DATA(lx_context).
        CLEAR current_user.
    ENDTRY.

    MODIFY ENTITIES OF zi_pr_header_ad IN LOCAL MODE
      ENTITY PurchaseRequisition
        UPDATE FIELDS ( Requester )
        WITH VALUE #(
          FOR key IN keys
          ( %tky      = key-%tky
            Requester = current_user ) ).
  ENDMETHOD.


  METHOD setPRNumber.
    READ ENTITIES OF zi_pr_header_ad IN LOCAL MODE
      ENTITY PurchaseRequisition
        FIELDS ( Status PrNumber )
        WITH CORRESPONDING #( keys )
      RESULT DATA(prs).

    " NOTE: no "DATA update TYPE TABLE FOR UPDATE ..." here on purpose -
    " see the workaround note at the top of this file. MODIFY ENTITIES
    " is called once per row instead, with the WITH table built inline.
    LOOP AT prs INTO DATA(pr) WHERE Status = status-pending AND PrNumber IS INITIAL.

      TRY.
          cl_numberrange_runtime=>number_get(
            EXPORTING
              nr_range_nr = '01'
              object      = 'ZPR_NR_AD'
            IMPORTING
              number      = DATA(lv_number) ).
        CATCH cx_number_ranges INTO DATA(lx_number_ranges).
          APPEND VALUE #( %tky        = pr-%tky
                           %state_area = 'SET_PR_NUMBER'
                           %msg        = new_message_with_text(
                                           severity = if_abap_behv_message=>severity-error
                                           text     = |Purchase requisition number could not be | &&
                                                      |assigned: { lx_number_ranges->get_text( ) }| ) )
            TO reported-purchaserequisition.
          CONTINUE.
      ENDTRY.

      MODIFY ENTITIES OF zi_pr_header_ad IN LOCAL MODE
        ENTITY PurchaseRequisition
          UPDATE FIELDS ( PrNumber )
          WITH VALUE #( ( %tky      = pr-%tky
                           PrNumber  = lv_number ) ).
    ENDLOOP.
  ENDMETHOD.


  METHOD calculateTotal.
    READ ENTITIES OF zi_pr_header_ad IN LOCAL MODE
      ENTITY PurchaseRequisition BY \_Item
        FIELDS ( Amount )
        WITH CORRESPONDING #( keys )
      RESULT DATA(items)
      LINK DATA(links).

    LOOP AT keys INTO DATA(key).
      DATA(total_amount) = VALUE zpr_header_ad-total_amount( ).

      LOOP AT links INTO DATA(link) WHERE source = key-%tky.
        READ TABLE items WITH KEY %tky = link-target INTO DATA(item).
        IF sy-subrc = 0.
          total_amount += item-Amount.
        ENDIF.
      ENDLOOP.

      MODIFY ENTITIES OF zi_pr_header_ad IN LOCAL MODE
        ENTITY PurchaseRequisition
          UPDATE FIELDS ( TotalAmount )
          WITH VALUE #( ( %tky        = key-%tky
                           TotalAmount = total_amount ) ).
    ENDLOOP.
  ENDMETHOD.


  METHOD setApprovalData.
    READ ENTITIES OF zi_pr_header_ad IN LOCAL MODE
      ENTITY PurchaseRequisition
        FIELDS ( Status Approver )
        WITH CORRESPONDING #( keys )
      RESULT DATA(prs).

    TRY.
        DATA(current_user) = cl_abap_context_info=>get_user_technical_name( ).
      CATCH cx_abap_context_info_error INTO DATA(lx_context).
        CLEAR current_user.
    ENDTRY.

    LOOP AT prs INTO DATA(pr) WHERE Status = status-approved AND Approver IS INITIAL.
      MODIFY ENTITIES OF zi_pr_header_ad IN LOCAL MODE
        ENTITY PurchaseRequisition
          UPDATE FIELDS ( Approver ApprovedAt )
          WITH VALUE #( ( %tky        = pr-%tky
                           Approver    = current_user
                           ApprovedAt  = cl_abap_tstmp=>utclong2tstmp( utclong_current( ) ) ) ).
    ENDLOOP.
  ENDMETHOD.


  METHOD validateAmount.
    READ ENTITIES OF zi_pr_header_ad IN LOCAL MODE
      ENTITY PurchaseRequisition
        FIELDS ( TotalAmount )
        WITH CORRESPONDING #( keys )
      RESULT DATA(prs).

    LOOP AT prs INTO DATA(pr) WHERE TotalAmount <= 0.
      APPEND VALUE #( %tky = pr-%tky ) TO failed-purchaserequisition.

      APPEND VALUE #( %tky        = pr-%tky
                       %state_area = 'VALIDATE_AMOUNT'
                       %msg        = new_message_with_text(
                                       severity = if_abap_behv_message=>severity-error
                                       text     = 'Total amount must be greater than zero' ) )
        TO reported-purchaserequisition.
    ENDLOOP.
  ENDMETHOD.


  METHOD validateItems.
    READ ENTITIES OF zi_pr_header_ad IN LOCAL MODE
      ENTITY PurchaseRequisition BY \_Item
        FIELDS ( Material )
        WITH CORRESPONDING #( keys )
      RESULT DATA(items)
      LINK DATA(links).

    LOOP AT keys INTO DATA(key).
      READ TABLE links WITH KEY source = key-%tky TRANSPORTING NO FIELDS.
      IF sy-subrc <> 0.
        APPEND VALUE #( %tky = key-%tky ) TO failed-purchaserequisition.

        APPEND VALUE #( %tky        = key-%tky
                         %state_area = 'VALIDATE_ITEMS'
                         %msg        = new_message_with_text(
                                         severity = if_abap_behv_message=>severity-error
                                         text     = 'At least one item is required' ) )
          TO reported-purchaserequisition.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD validateRejectReason.
    READ ENTITIES OF zi_pr_header_ad IN LOCAL MODE
      ENTITY PurchaseRequisition
        FIELDS ( Status RejectReason )
        WITH CORRESPONDING #( keys )
      RESULT DATA(prs).

    LOOP AT prs INTO DATA(pr) WHERE Status = status-rejected AND RejectReason IS INITIAL.
      APPEND VALUE #( %tky = pr-%tky ) TO failed-purchaserequisition.

      APPEND VALUE #( %tky        = pr-%tky
                       %state_area = 'VALIDATE_REJECT_REASON'
                       %msg        = new_message_with_text(
                                       severity = if_abap_behv_message=>severity-error
                                       text     = 'Rejection reason is required' ) )
        TO reported-purchaserequisition.
    ENDLOOP.
  ENDMETHOD.


  METHOD submit.
    READ ENTITIES OF zi_pr_header_ad IN LOCAL MODE
      ENTITY PurchaseRequisition
        FIELDS ( Status )
        WITH CORRESPONDING #( keys )
      RESULT DATA(prs).

    LOOP AT prs INTO DATA(pr) WHERE Status = status-draft OR Status = status-info_req.
      MODIFY ENTITIES OF zi_pr_header_ad IN LOCAL MODE
        ENTITY PurchaseRequisition
          UPDATE FIELDS ( Status )
          WITH VALUE #( ( %tky   = pr-%tky
                           Status = status-pending ) ).
    ENDLOOP.

    READ ENTITIES OF zi_pr_header_ad IN LOCAL MODE
      ENTITY PurchaseRequisition
        ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(result_prs).

    result = VALUE #(
      FOR result_pr IN result_prs
      ( %tky   = result_pr-%tky
        %param = result_pr ) ).
  ENDMETHOD.


  METHOD approve.
    MODIFY ENTITIES OF zi_pr_header_ad IN LOCAL MODE
      ENTITY PurchaseRequisition
        UPDATE FIELDS ( Status )
        WITH VALUE #(
          FOR key IN keys
          ( %tky   = key-%tky
            Status = status-approved ) ).

    READ ENTITIES OF zi_pr_header_ad IN LOCAL MODE
      ENTITY PurchaseRequisition
        ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(result_prs).

    result = VALUE #(
      FOR result_pr IN result_prs
      ( %tky   = result_pr-%tky
        %param = result_pr ) ).
  ENDMETHOD.


  METHOD reject.
    MODIFY ENTITIES OF zi_pr_header_ad IN LOCAL MODE
      ENTITY PurchaseRequisition
        UPDATE FIELDS ( Status RejectReason )
        WITH VALUE #(
          FOR key IN keys
          ( %tky          = key-%tky
            Status        = status-rejected
            RejectReason  = key-%param-reject_reason ) ).

    READ ENTITIES OF zi_pr_header_ad IN LOCAL MODE
      ENTITY PurchaseRequisition
        ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(result_prs).

    result = VALUE #(
      FOR result_pr IN result_prs
      ( %tky   = result_pr-%tky
        %param = result_pr ) ).
  ENDMETHOD.


  METHOD requestInfo.
    MODIFY ENTITIES OF zi_pr_header_ad IN LOCAL MODE
      ENTITY PurchaseRequisition
        UPDATE FIELDS ( Status )
        WITH VALUE #(
          FOR key IN keys
          ( %tky   = key-%tky
            Status = status-info_req ) ).

    READ ENTITIES OF zi_pr_header_ad IN LOCAL MODE
      ENTITY PurchaseRequisition
        ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(result_prs).

    result = VALUE #(
      FOR result_pr IN result_prs
      ( %tky   = result_pr-%tky
        %param = result_pr ) ).
  ENDMETHOD.

ENDCLASS.


CLASS lhc_purchaserequisitionitem DEFINITION INHERITING FROM cl_abap_behavior_handler.

  PRIVATE SECTION.

    METHODS setItemNumber FOR DETERMINE ON MODIFY
      IMPORTING keys FOR PurchaseRequisitionItem~setItemNumber.

    METHODS setItemCurrency FOR DETERMINE ON MODIFY
      IMPORTING keys FOR PurchaseRequisitionItem~setItemCurrency.

    METHODS calculateItemAmount FOR DETERMINE ON MODIFY
      IMPORTING keys FOR PurchaseRequisitionItem~calculateItemAmount.

ENDCLASS.


CLASS lhc_purchaserequisitionitem IMPLEMENTATION.

  METHOD setItemNumber.

    READ ENTITIES OF zi_pr_header_ad IN LOCAL MODE
      ENTITY PurchaseRequisitionItem BY \_Header
        FIELDS ( PrUuid )
        WITH CORRESPONDING #( keys )
      RESULT DATA(headers)
      LINK DATA(header_links).

    DATA distinct_headers LIKE headers.
    LOOP AT headers INTO DATA(header).
      IF NOT line_exists( distinct_headers[ %tky = header-%tky ] ).
        distinct_headers = VALUE #( BASE distinct_headers ( header ) ).
      ENDIF.
    ENDLOOP.

    READ ENTITIES OF zi_pr_header_ad IN LOCAL MODE
      ENTITY PurchaseRequisition BY \_Item
        FIELDS ( ItemNumber )
        WITH CORRESPONDING #( distinct_headers )
      RESULT DATA(sibling_items)
      LINK DATA(sibling_links).

    LOOP AT distinct_headers INTO header.
      DATA(next_number) = VALUE zpr_item_ad-item_number( ).

      LOOP AT sibling_links INTO DATA(sibling_link) WHERE source = header-%tky.
        READ TABLE sibling_items WITH KEY %tky = sibling_link-target INTO DATA(sibling).
        IF sy-subrc = 0 AND sibling-ItemNumber > next_number.
          next_number = sibling-ItemNumber.
        ENDIF.
      ENDLOOP.

      LOOP AT header_links INTO DATA(header_link) WHERE target = header-%tky.
        next_number += 10.
        MODIFY ENTITIES OF zi_pr_header_ad IN LOCAL MODE
          ENTITY PurchaseRequisitionItem
            UPDATE FIELDS ( ItemNumber )
            WITH VALUE #( ( %tky        = header_link-source
                             ItemNumber  = next_number ) ).
      ENDLOOP.
    ENDLOOP.
  ENDMETHOD.


  METHOD setItemCurrency.

    READ ENTITIES OF zi_pr_header_ad IN LOCAL MODE
      ENTITY PurchaseRequisitionItem BY \_Header
        FIELDS ( Currency )
        WITH CORRESPONDING #( keys )
      RESULT DATA(headers)
      LINK DATA(header_links).

    LOOP AT header_links INTO DATA(header_link).
      READ TABLE headers WITH KEY %tky = header_link-target INTO DATA(header).
      IF sy-subrc = 0.
        MODIFY ENTITIES OF zi_pr_header_ad IN LOCAL MODE
          ENTITY PurchaseRequisitionItem
            UPDATE FIELDS ( Currency )
            WITH VALUE #( ( %tky      = header_link-source
                             Currency  = header-Currency ) ).
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD calculateItemAmount.
    READ ENTITIES OF zi_pr_header_ad IN LOCAL MODE
      ENTITY PurchaseRequisitionItem
        FIELDS ( ParentUuid Quantity Price )
        WITH CORRESPONDING #( keys )
      RESULT DATA(items).

    MODIFY ENTITIES OF zi_pr_header_ad IN LOCAL MODE
      ENTITY PurchaseRequisitionItem
        UPDATE FIELDS ( Amount )
        WITH VALUE #(
          FOR item IN items
          ( %tky   = item-%tky
            Amount = item-Quantity * item-Price ) ).

    " NOTE: no "DATA headers TYPE TABLE FOR EXECUTE ..." here on purpose
    " - same workaround as setPRNumber above. Deduplication of parent
    " headers is done with a plain sysuuid_x16 table instead.
    DATA processed_parents TYPE STANDARD TABLE OF sysuuid_x16 WITH EMPTY KEY.

    LOOP AT items INTO DATA(row).
      IF NOT line_exists( processed_parents[ table_line = row-ParentUuid ] ).
        APPEND row-ParentUuid TO processed_parents.

        MODIFY ENTITIES OF zi_pr_header_ad IN LOCAL MODE
          ENTITY PurchaseRequisition
            EXECUTE recalcTotal
            FROM VALUE #( ( %tky-PrUuid = row-ParentUuid ) ).
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
