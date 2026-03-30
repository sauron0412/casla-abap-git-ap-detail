CLASS zcl_accpay_detail DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC .
  PUBLIC SECTION.
    INTERFACES if_rap_query_provider.
  PROTECTED SECTION.
  PRIVATE SECTION.
    " Define line item structure internally
    TYPES: BEGIN OF ty_line_item,
             posting_date        TYPE budat,
             document_number     TYPE belnr_d,
             document_date       TYPE bldat,
             contra_account      TYPE saknr,
             item_text           TYPE sgtxt,
             profit_center       TYPE prctr,
             debit_amount        TYPE wrbtr,
             credit_amount       TYPE wrbtr,
             balance             TYPE wrbtr,
             closingdebit        TYPE wrbtr,
             closingcredit       TYPE wrbtr,
             debit_amount_tran   TYPE wrbtr,
             credit_amount_tran  TYPE wrbtr,
             balance_tran        TYPE wrbtr,
             closingdebit_tran   TYPE wrbtr,
             closingcredit_tran  TYPE wrbtr,
             companycodecurrency TYPE waers,
             transactioncurrency TYPE waers,
           END OF ty_line_item.

    TYPES: ty_ledgergllineitem TYPE c LENGTH 6.

    TYPES: tt_line_items TYPE TABLE OF zst_line_item_detail.

    TYPES: BEGIN OF ty_journal_item,
             companycode                 TYPE bukrs,
             fiscalyear                  TYPE gjahr,
             accountingdocument          TYPE belnr_d,
             ledgergllineitem            TYPE ty_ledgergllineitem,
             originalreferencedocument   TYPE awkey,
             reversalreferencedocument   TYPE belnr_d,
             postingdate                 TYPE budat,
             documentdate                TYPE bldat,
             glaccount                   TYPE saknr,
             supplier                    TYPE lifnr,
*             customer                    TYPE kunnr,
             amountincompanycodecurrency TYPE wrbtr,
             amountintransactioncurrency TYPE wrbtr,
             debitcreditcode             TYPE shkzg,
             accountingdocumenttype      TYPE blart,
             documentitemtext            TYPE sgtxt,
             profitcenter                TYPE prctr,
             isreversed                  TYPE abap_bool,
             companycodecurrency         TYPE waers,
             transactioncurrency         TYPE waers,
           END OF ty_journal_item.

    TYPES: tt_journal_items TYPE TABLE OF ty_journal_item.

    METHODS get_company_info
      IMPORTING iv_bukrs           TYPE bukrs
      EXPORTING ev_company_name    TYPE text100
                ev_company_address TYPE char256.

    METHODS get_business_partner_name
      IMPORTING iv_business_partner TYPE text10
      RETURNING VALUE(rv_name)      TYPE text100.

    METHODS get_opening_balance
      IMPORTING iv_bukrs        TYPE bukrs
                iv_racct        TYPE saknr
                iv_partner      TYPE text10
                iv_date         TYPE datum
                iv_currency     TYPE waers
      EXPORTING ev_debit        TYPE wrbtr
                ev_credit       TYPE wrbtr
                ev_balance      TYPE wrbtr
                ev_debit_tran   TYPE wrbtr
                ev_credit_tran  TYPE wrbtr
                ev_balance_tran TYPE wrbtr.

    METHODS process_period_data
      IMPORTING it_journal_items     TYPE tt_journal_items
                iv_bukrs             TYPE bukrs
                iv_racct             TYPE saknr
                iv_partner           TYPE text10
                iv_date_from         TYPE datum
                iv_date_to           TYPE datum
                iv_currency          TYPE waers
      EXPORTING et_line_items        TYPE tt_line_items
                ev_debit_total       TYPE wrbtr
                ev_credit_total      TYPE wrbtr
                ev_debit_total_tran  TYPE wrbtr
                ev_credit_total_tran TYPE wrbtr.

    METHODS get_contra_account
      IMPORTING iv_bukrs         TYPE bukrs
                iv_accountingdoc TYPE belnr_d
                iv_fiscalyear    TYPE gjahr
                iv_racct         TYPE saknr
                iv_lineitem      TYPE ty_ledgergllineitem
      RETURNING VALUE(rv_contra) TYPE saknr.

    METHODS determine_account_nature
      IMPORTING iv_glaccount     TYPE saknr
      RETURNING VALUE(rv_nature) TYPE char1_run_type.

    METHODS convert_line_items_to_json
      IMPORTING it_line_items  TYPE tt_line_items
      RETURNING VALUE(rv_json) TYPE string.

ENDCLASS.



CLASS ZCL_ACCPAY_DETAIL IMPLEMENTATION.


  METHOD convert_line_items_to_json.
    " Convert internal table to JSON string
    DATA: lo_writer TYPE REF TO cl_sxml_string_writer.

    lo_writer = cl_sxml_string_writer=>create( type = if_sxml=>co_xt_json ).

    CALL TRANSFORMATION id
      SOURCE line_items = it_line_items
      RESULT XML lo_writer.

    rv_json = cl_abap_conv_codepage=>create_in( )->convert( lo_writer->get_output( ) ).

  ENDMETHOD.


  METHOD determine_account_nature.
    " Determine if account is debit or credit nature based on GL account number
    DATA: lv_first_char TYPE c LENGTH 1,
          lv_first_two  TYPE c LENGTH 2,
          lv_first_four TYPE c LENGTH 4.
    " remove leading zeros for accurate classification
    DATA(lv_glaccount) = |{ iv_glaccount ALPHA = OUT  }|.
    lv_first_char = lv_glaccount(1).
    lv_first_two = lv_glaccount(2).
    lv_first_four = lv_glaccount(4).

    " Special handling for certain accounts
    IF lv_first_four = '1312'.
      rv_nature = 'C'. " Credit nature
      RETURN.
    ELSEIF lv_first_four = '3312'.
      rv_nature = 'D'. " Debit nature
      RETURN.
    ENDIF.

    " Standard account classification
    IF lv_first_char = '1' OR lv_first_char = '2' OR
       lv_first_char = '6' OR lv_first_char = '8' OR
       lv_first_two = 'Z1'.
      rv_nature = 'D'. " Debit nature (Assets, Expenses)
    ELSE.
      rv_nature = 'C'. " Credit nature (Liabilities, Revenue, Equity)
    ENDIF.

  ENDMETHOD.


  METHOD get_business_partner_name.
    DATA: lv_name TYPE string.

    " First try to get from I_BusinessPartner
    SELECT SINGLE businesspartnername
      FROM i_businesspartner
      WHERE businesspartner = @iv_business_partner
      INTO @lv_name.

    IF lv_name IS NOT INITIAL.
      rv_name = lv_name.
      RETURN.
    ENDIF.

    " If not found, try supplier master
    SELECT SINGLE suppliername
      FROM i_supplier
      WHERE supplier = @iv_business_partner
      INTO @lv_name.

    IF lv_name IS NOT INITIAL.
      rv_name = lv_name.
      RETURN.
    ENDIF.

    " If not found, try customer master
    SELECT SINGLE customername
      FROM i_customer
      WHERE customer = @iv_business_partner
      INTO @lv_name.

    IF lv_name IS NOT INITIAL.
      rv_name = lv_name.
      RETURN.
    ENDIF.

    " If still nothing found, return the BP number
    rv_name = |BP: { iv_business_partner }|.

  ENDMETHOD.


  METHOD get_company_info.
    SELECT SINGLE
              companycode,
              addressid,
              vatregistration,
              currency,
              companycodename
    FROM i_companycode
    WHERE companycode = @iv_bukrs
    INTO @DATA(ls_company).
    .

    zcl_jp_common_core=>get_address_id_details(
      EXPORTING
        addressid            = ls_company-addressid
      IMPORTING
        o_addressiddetails = DATA(ls_addressid_dtails)
    ).

    ev_company_name = ls_company-companycodename.
    ev_company_address = ls_addressid_dtails-address.

  ENDMETHOD.


  METHOD get_contra_account.
    " Get other line items from the same document
    SELECT glaccount, amountincompanycodecurrency
*      FROM i_journalentryitem
      FROM i_glaccountlineitem
      WHERE companycode = @iv_bukrs
        AND accountingdocument = @iv_accountingdoc
        AND fiscalyear = @iv_fiscalyear
*        AND ledgergllineitem <> @iv_lineitem
        AND offsettingledgergllineitem = @iv_lineitem
*        AND glaccount <> @iv_racct
        AND ledger = '0L'
      ORDER BY amountincompanycodecurrency DESCENDING
      INTO @DATA(ls_contra)
      UP TO 1 ROWS.

      rv_contra = ls_contra-glaccount.
    ENDSELECT.

  ENDMETHOD.


  METHOD get_opening_balance.
    DATA: lv_total_amount TYPE i_journalentryitem-amountincompanycodecurrency.
    DATA: lt_where_clauses TYPE TABLE OF string.

    APPEND | supplier = @iv_partner| TO lt_where_clauses.
    APPEND |AND postingdate < @iv_date| TO lt_where_clauses.
    APPEND |AND companycode = @iv_bukrs| TO lt_where_clauses.
    APPEND |AND ledger = '0L'| TO lt_where_clauses.
    APPEND |AND financialaccounttype = 'K'| TO lt_where_clauses.
    APPEND |AND supplier IS NOT NULL| TO lt_where_clauses.
    APPEND |AND debitcreditcode IN ('S', 'H')| TO lt_where_clauses.
    APPEND |AND glaccount = @iv_racct| TO lt_where_clauses.

    IF iv_currency IS NOT INITIAL.
      APPEND |AND transactioncurrency = @iv_currency| TO lt_where_clauses.
    ENDIF.
    SELECT supplier AS bp,
           companycode AS rbukrs,
*           glaccount as GLAccountNumber,
           SUM( CASE WHEN debitcreditcode = 'S' THEN amountincompanycodecurrency ELSE 0 END ) AS open_debit,
           SUM( CASE WHEN debitcreditcode = 'H' THEN amountincompanycodecurrency ELSE 0 END ) AS open_credit,
           SUM( CASE WHEN debitcreditcode = 'S' THEN amountintransactioncurrency ELSE 0 END ) AS open_debit_tran,
           SUM( CASE WHEN debitcreditcode = 'H' THEN amountintransactioncurrency ELSE 0 END ) AS open_credit_tran,
           transactioncurrency,
           companycodecurrency,
           glaccount
      FROM i_journalentryitem
      WHERE (lt_where_clauses)
*      WHERE supplier = @iv_partner
*        AND postingdate < @iv_date
*        AND companycode = @iv_bukrs
*        AND ledger = '0L'
*        AND financialaccounttype = 'K'
*        AND supplier IS NOT NULL
*        AND debitcreditcode IN ('S', 'H')
*        AND glaccount = @iv_racct
**        AND transactioncurrency = @iv_currency
      GROUP BY supplier, companycode,transactioncurrency, companycodecurrency, glaccount
      INTO TABLE @DATA(lt_open_balances).
    SORT lt_open_balances BY rbukrs bp.
    CLEAR : ev_balance,ev_balance_tran.
*    LOOP AT lt_open_balances INTO DATA(ls_open_balance) WHERE rbukrs = iv_bukrs AND bp = iv_partner.
*      ev_balance =  ev_balance + ls_open_balance-open_debit + ls_open_balance-open_credit.
*      IF iv_currency = ''.
*        IF ls_open_balance-transactioncurrency = 'USD'.
*          ev_balance_tran = ev_balance_tran + ls_open_balance-open_debit_tran + ls_open_balance-open_credit_tran.
*        ENDIF.
*      ELSE.
*        ev_balance_tran = ev_balance_tran + ls_open_balance-open_debit_tran + ls_open_balance-open_credit_tran.
*      ENDIF.
*    ENDLOOP.
    READ TABLE lt_open_balances INTO DATA(ls_open_balance) WITH KEY  rbukrs = iv_bukrs
                                                                     bp = iv_partner
                                                                     .
    IF sy-subrc = 0.
      ev_balance = ls_open_balance-open_debit + ls_open_balance-open_credit.
      IF ev_balance < 0.
        ev_credit = ev_balance * -1.
        ev_debit = 0.
      ELSE.
        ev_debit = ev_balance.
        ev_credit = 0.
      ENDIF.
    ENDIF.
    ev_balance_tran = ls_open_balance-open_debit_tran + ls_open_balance-open_credit_tran.
    IF ev_balance_tran < 0.
      ev_credit_tran = ev_balance_tran * -1.
      ev_debit_tran = 0.
    ELSE.
      ev_debit_tran = ev_balance_tran.
      ev_credit_tran = 0.
    ENDIF.

  ENDMETHOD.


  METHOD if_rap_query_provider~select.
    DATA: lt_result     TYPE TABLE OF zc_accpay_detail,
          lt_result1    TYPE TABLE OF zc_accpay_detail,
          lt_result_kps TYPE TABLE OF zc_accpay_detail,
          ls_result     TYPE zc_accpay_detail.

    DATA: lt_journal_items     TYPE tt_journal_items,
          lt_journal_items_kps TYPE tt_journal_items,
          lt_journal_items_tmp TYPE tt_journal_items,
          lr_currency          TYPE RANGE OF i_journalentryitem-transactioncurrency,
          lt_line_items_tmp    TYPE tt_line_items,
          lt_line_items        TYPE tt_line_items.

    TRY.
        " Get request details
        DATA(lo_filter) = io_request->get_filter( ).
        DATA(lt_filters) = lo_filter->get_as_ranges( ).

        " Extract filter values
        DATA(lr_bukrs) = lt_filters[ name = 'COMPANYCODE' ]-range.
*        DATA(lr_racct) = lt_filters[ name = 'GLACCOUNTNUMBER' ]-range.
        DATA(lr_date_from) = lt_filters[ name = 'POSTINGDATEFROM' ]-range.
        DATA(lr_date_to) = lt_filters[ name = 'POSTINGDATETO' ]-range.
*        READ TABLE lt_filters INTO DATA(ls_filters) WITH KEY name = 'TRANSACTIONCURRENCY'.
*        IF sy-subrc = 0.
*          lr_currency[] = lt_filters[ name = 'TRANSACTIONCURRENCY' ]-range."[ 1 ]-low.
*        ENDIF.
*
*        TRY.
*            DATA(lr_currencry_raw) = lt_filters[ name = 'TRANSACTIONCURRENCY' ]-range.
**             Apply alpha conversion for GL accounts
*
*            MOVE-CORRESPONDING lr_currencry_raw TO lr_currency.
**            lv_glaccount_provided = abap_true.
*          CATCH cx_sy_itab_line_not_found.
** GL Account filter not provided - will select all GL accounts
*            CLEAR lr_currency.
**            lv_glaccount_provided = abap_false.
*        ENDTRY.
* Handle optional GL Account filter
        DATA: lr_racct              TYPE RANGE OF i_journalentryitem-glaccount,
              lv_glaccount_provided TYPE abap_bool.

        TRY.
            DATA(lr_racct_raw) = lt_filters[ name = 'GLACCOUNTNUMBER' ]-range.
*             Apply alpha conversion for GL accounts
            LOOP AT lr_racct_raw ASSIGNING FIELD-SYMBOL(<fs_glaccount>).
              IF <fs_glaccount>-low IS NOT INITIAL.
                <fs_glaccount>-low = |{ <fs_glaccount>-low ALPHA = IN WIDTH = 10 }|.
              ENDIF.
              IF <fs_glaccount>-high IS NOT INITIAL.
                <fs_glaccount>-high = |{ <fs_glaccount>-high ALPHA = IN WIDTH = 10 }|.
              ENDIF.
            ENDLOOP.
            MOVE-CORRESPONDING lr_racct_raw TO lr_racct.
            lv_glaccount_provided = abap_true.
          CATCH cx_sy_itab_line_not_found.
* GL Account filter not provided - will select all GL accounts
            CLEAR lr_racct.
            lv_glaccount_provided = abap_false.
        ENDTRY.


      CATCH cx_rap_query_filter_no_range INTO DATA(lx_no_range).
        " Handle error
        RETURN.
    ENDTRY.
    " Safely extract optional filters and check if provided
    DATA: lv_partner_provided      TYPE abap_bool,
          lv_profitcenter_provided TYPE abap_bool,
          lv_currency_prov         TYPE abap_bool,
          lr_partner               TYPE RANGE OF i_journalentryitem-supplier,
          lr_profitcenter          TYPE RANGE OF i_journalentryitem-profitcenter.
*
    TRY.
        DATA(lr_currency_raw) = lt_filters[ name = 'TRANSACTIONCURRENCY' ]-range. "COMPANYCODECURRENCY
        LOOP AT lr_currency_raw ASSIGNING FIELD-SYMBOL(<fs_currency>).
          IF <fs_currency>-low IS NOT INITIAL.
            <fs_currency>-low = |{ <fs_currency>-low ALPHA = IN WIDTH = 5 }|.
          ENDIF.
          IF <fs_currency>-high IS NOT INITIAL.
            <fs_currency>-high = |{ <fs_currency>-high ALPHA = IN WIDTH = 5 }|.
          ENDIF.
        ENDLOOP.
        MOVE-CORRESPONDING lr_currency_raw TO lr_currency.
        lv_currency_prov = abap_true.
      CATCH cx_sy_itab_line_not_found.
        CLEAR lr_currency.
    ENDTRY.

    TRY.
        DATA(lr_partner_raw) = lt_filters[ name = 'BUSINESSPARTNER' ]-range.
        LOOP AT lr_partner_raw ASSIGNING FIELD-SYMBOL(<fs_partner>).
          IF <fs_partner>-low IS NOT INITIAL.
            <fs_partner>-low = |{ <fs_partner>-low ALPHA = IN WIDTH = 10 }|.
          ENDIF.
          IF <fs_partner>-high IS NOT INITIAL.
            <fs_partner>-high = |{ <fs_partner>-high ALPHA = IN WIDTH = 10 }|.
          ENDIF.
        ENDLOOP.
        MOVE-CORRESPONDING lr_partner_raw TO lr_partner.
        lv_partner_provided = abap_true.
      CATCH cx_sy_itab_line_not_found.
        CLEAR lr_partner.
    ENDTRY.

    TRY.
        DATA(lr_profitcenter_raw) = lt_filters[ name = 'PROFITCENTER' ]-range.
        LOOP AT lr_profitcenter_raw ASSIGNING FIELD-SYMBOL(<fs_profitcenter>).
          <fs_profitcenter>-low = |{ <fs_profitcenter>-low ALPHA = IN WIDTH = 10 }|.
          IF <fs_profitcenter>-high IS NOT INITIAL.
            <fs_profitcenter>-high = |{ <fs_profitcenter>-high ALPHA = IN WIDTH = 10 }|.
          ENDIF.
        ENDLOOP.
        MOVE-CORRESPONDING lr_profitcenter_raw TO lr_profitcenter.
        lv_profitcenter_provided = abap_true.
      CATCH cx_sy_itab_line_not_found.
        CLEAR lr_profitcenter.
    ENDTRY.

    DATA: lv_bukrs           TYPE bukrs,
          lv_racct           TYPE saknr,
          lv_partner         TYPE text10,
          lv_date_from       TYPE datum,
          lv_date_to         TYPE datum,
          lv_company_name    TYPE zc_accpay_detail-companyname,
          lv_company_address TYPE char256,
          lv_closing         TYPE zc_accpay_detail-closingcredit.

    " Get single values
    lv_bukrs = lr_bukrs[ 1 ]-low.
    lv_date_from = lr_date_from[ 1 ]-low.
    lv_date_to = COND #( WHEN lr_date_to[ 1 ]-low IS NOT INITIAL
                          THEN lr_date_to[ 1 ]-low
                          ELSE lv_date_from ).

    " Get company info
*    get_company_info(
*      EXPORTING
*        iv_bukrs = lv_bukrs
*      IMPORTING
*        ev_company_name = lv_company_name
*        ev_company_address = lv_company_address ).

*        " Get business partner name
*        ls_result-businesspartnername = get_business_partner_name( lv_partner ).

    DATA: lw_company          TYPE bukrs,
          ls_companycode_info TYPE zst_companycode_info.

    lw_company = lr_bukrs[ 1 ]-low.
    CALL METHOD zcl_jp_common_core=>get_companycode_details
      EXPORTING
        i_companycode = lw_company
      IMPORTING
        o_companycode = ls_companycode_info.

    DATA: lt_where_clauses TYPE TABLE OF string.

    APPEND |companycode = '{ lv_bukrs }'| TO lt_where_clauses.
*    APPEND |and glaccount IN @lr_racct| TO lt_where_clauses.
    IF lv_glaccount_provided = abap_true.
      APPEND |and glaccount IN @lr_racct| TO lt_where_clauses.
    ENDIF.
    APPEND |and postingdate BETWEEN '{ lv_date_from }' AND '{ lv_date_to }'| TO lt_where_clauses.
    APPEND |and ledger = '0L'| TO lt_where_clauses.
*    APPEND |and isreversed = @abap_false| TO lt_where_clauses.
    APPEND |and financialaccounttype = 'K'| TO lt_where_clauses.
    APPEND |and AccountingDocument NOT LIKE 'B%'| TO lt_where_clauses.
*    APPEND |and TRANSACTIONCURRENCY in @lr_currency| TO lt_where_clauses.

    IF lv_partner_provided = abap_true.
      APPEND |and supplier IN @lr_partner| TO lt_where_clauses.
    ENDIF.

    IF lv_profitcenter_provided = abap_true.
      APPEND |and ProfitCenter IN @lr_profitcenter| TO lt_where_clauses.
    ENDIF.
    READ TABLE lr_currency INTO DATA(ls_currency) INDEX 1.
    IF lv_currency_prov = abap_true AND ls_currency-low NE 'VND'.
      APPEND |and TRANSACTIONCURRENCY in @lr_currency| TO lt_where_clauses.
    ENDIF.

    SELECT companycode,
           fiscalyear,
           accountingdocument,
           ledgergllineitem,
           postingdate,
           documentdate,
           glaccount,
           supplier,
           amountincompanycodecurrency,
           amountintransactioncurrency,
           companycodecurrency,
           transactioncurrency,
           debitcreditcode,
           accountingdocumenttype,
           documentitemtext,
           profitcenter,
           isreversed
      FROM i_journalentryitem
      WHERE (lt_where_clauses)
      INTO CORRESPONDING FIELDS OF TABLE @lt_journal_items.
********************************************************************** Logic huy
    lt_journal_items_tmp = lt_journal_items.
    SORT lt_journal_items_tmp BY companycode accountingdocument fiscalyear.
    DELETE ADJACENT DUPLICATES FROM lt_journal_items_tmp COMPARING companycode accountingdocument fiscalyear.
    IF lt_journal_items_tmp IS NOT INITIAL.
      SELECT companycode,
             fiscalyear,
             accountingdocument,
             originalreferencedocument,
             reversalreferencedocument
           FROM i_journalentry
           FOR ALL ENTRIES IN @lt_journal_items_tmp
           WHERE companycode = @lt_journal_items_tmp-companycode
           AND   fiscalyear = @lt_journal_items_tmp-fiscalyear
           AND   accountingdocument = @lt_journal_items_tmp-accountingdocument
           INTO TABLE @DATA(lt_original).
      SORT lt_original BY companycode fiscalyear accountingdocument.
      LOOP AT lt_journal_items ASSIGNING FIELD-SYMBOL(<fs_item>).
        READ TABLE lt_original INTO DATA(ls_original) WITH KEY companycode = <fs_item>-companycode
                                                               fiscalyear = <fs_item>-fiscalyear
                                                               accountingdocument = <fs_item>-accountingdocument.
        IF sy-subrc = 0.
          <fs_item>-originalreferencedocument = ls_original-originalreferencedocument.
          <fs_item>-reversalreferencedocument = ls_original-reversalreferencedocument.
        ENDIF.
      ENDLOOP.
    ENDIF.
**********************************************************************
    CLEAR : lt_journal_items_tmp.
    lt_journal_items_tmp = lt_journal_items.
    SORT lt_journal_items_tmp BY companycode accountingdocument fiscalyear.
    LOOP AT lt_journal_items_tmp INTO DATA(ls_doc1) WHERE isreversed = 'X'.


      READ TABLE lt_journal_items INTO DATA(ls_doc2)
           WITH KEY companycode        = ls_doc1-companycode
                    fiscalyear = ls_doc1-fiscalyear
                    reversalreferencedocument = ls_doc1-originalreferencedocument(10).

      IF sy-subrc = 0 AND ls_doc1-postingdate+4(2) = ls_doc2-postingdate+4(2) AND ls_doc1-postingdate(4) = ls_doc2-postingdate(4). " Cung ky moi xoa.
        DELETE lt_journal_items WHERE (  accountingdocument = ls_doc1-accountingdocument
                     OR accountingdocument = ls_doc2-accountingdocument ) AND companycode = ls_doc1-companycode AND fiscalyear = ls_doc1-fiscalyear.
      ENDIF.

    ENDLOOP.
**********************************************************************
    CLEAR : lt_where_clauses.
    APPEND |companycode = '{ lv_bukrs }'| TO lt_where_clauses.
*    APPEND |and glaccount IN @lr_racct| TO lt_where_clauses.
    IF lv_glaccount_provided = abap_true.
      APPEND |and glaccount IN @lr_racct| TO lt_where_clauses.
    ENDIF.
    APPEND |and postingdate < '{ lv_date_from }'| TO lt_where_clauses.
    APPEND |and ledger = '0L'| TO lt_where_clauses.
*    APPEND |and isreversed = @abap_false| TO lt_where_clauses.
    APPEND |and financialaccounttype = 'K'| TO lt_where_clauses.
    APPEND |and AccountingDocument NOT LIKE 'B%'| TO lt_where_clauses.
*    APPEND |and TRANSACTIONCURRENCY in @lr_currency| TO lt_where_clauses.

    IF lv_partner_provided = abap_true.
      APPEND |and supplier IN @lr_partner| TO lt_where_clauses.
    ENDIF.

    IF lv_profitcenter_provided = abap_true.
      APPEND |and ProfitCenter IN @lr_profitcenter| TO lt_where_clauses.
    ENDIF.

    IF lv_currency_prov = abap_true AND ls_currency-low NE 'VND'.
      APPEND |and TRANSACTIONCURRENCY in @lr_currency| TO lt_where_clauses.
    ENDIF.

    SELECT companycode,
           fiscalyear,
           accountingdocument,
           ledgergllineitem,
           postingdate,
           documentdate,
           glaccount,
           supplier,
           amountincompanycodecurrency,
           amountintransactioncurrency,
           companycodecurrency,
           transactioncurrency,
           debitcreditcode,
           accountingdocumenttype,
           documentitemtext,
           profitcenter,
           isreversed
      FROM i_journalentryitem
      WHERE (lt_where_clauses)
      INTO CORRESPONDING FIELDS OF TABLE @lt_journal_items_kps.
********************************************************************** Logic huy
    lt_journal_items_tmp = lt_journal_items_kps.
    SORT lt_journal_items_tmp BY companycode accountingdocument fiscalyear.
    DELETE ADJACENT DUPLICATES FROM lt_journal_items_tmp COMPARING companycode accountingdocument fiscalyear.
    IF lt_journal_items_tmp IS NOT INITIAL.
      SELECT companycode,
             fiscalyear,
             accountingdocument,
             originalreferencedocument,
             reversalreferencedocument
           FROM i_journalentry
           FOR ALL ENTRIES IN @lt_journal_items_tmp
           WHERE companycode = @lt_journal_items_tmp-companycode
           AND   fiscalyear = @lt_journal_items_tmp-fiscalyear
           AND   accountingdocument = @lt_journal_items_tmp-accountingdocument
           INTO TABLE @DATA(lt_original_kps).
      SORT lt_original_kps BY companycode fiscalyear accountingdocument.
      LOOP AT lt_journal_items_kps ASSIGNING FIELD-SYMBOL(<fs_item_kps>).
        READ TABLE lt_original_kps INTO DATA(ls_original_kps) WITH KEY companycode = <fs_item_kps>-companycode
                                                               fiscalyear = <fs_item_kps>-fiscalyear
                                                               accountingdocument = <fs_item_kps>-accountingdocument.
        IF sy-subrc = 0.
          <fs_item_kps>-originalreferencedocument = ls_original_kps-originalreferencedocument.
          <fs_item_kps>-reversalreferencedocument = ls_original_kps-reversalreferencedocument.
        ENDIF.
      ENDLOOP.
    ENDIF.
**********************************************************************
    CLEAR : lt_journal_items_tmp.
    lt_journal_items_tmp = lt_journal_items_kps.
    SORT lt_journal_items_tmp BY companycode accountingdocument fiscalyear.
    LOOP AT lt_journal_items_tmp INTO DATA(ls_doc1_kps) WHERE isreversed = 'X'.


      READ TABLE lt_journal_items_kps INTO DATA(ls_doc2_kps)
           WITH KEY companycode        = ls_doc1_kps-companycode
                    fiscalyear = ls_doc1_kps-fiscalyear
                    reversalreferencedocument = ls_doc1_kps-originalreferencedocument(10).

      IF sy-subrc = 0.
        DELETE lt_journal_items_kps WHERE (  accountingdocument = ls_doc1_kps-accountingdocument
                     OR accountingdocument = ls_doc2_kps-accountingdocument ) AND companycode = ls_doc1_kps-companycode AND fiscalyear = ls_doc1_kps-fiscalyear.
      ENDIF.

    ENDLOOP.
**********************************************************************
* Lay text
    IF lt_journal_items IS NOT INITIAL.
      SELECT a~companycode,
             a~accountingdocument,
             a~fiscalyear,
             b~ledgergllineitem,
             b~offsettingledgergllineitem,
             a~accountingdocumentheadertext,
             b~documentitemtext
      FROM i_journalentry AS a
      INNER JOIN i_glaccountlineitem AS b
      ON a~companycode = b~companycode
      AND a~accountingdocument = b~accountingdocument
      AND a~fiscalyear = b~fiscalyear
      FOR ALL ENTRIES IN @lt_journal_items
      WHERE a~companycode = @lt_journal_items-companycode
      AND   a~accountingdocument = @lt_journal_items-accountingdocument
      AND   a~fiscalyear = @lt_journal_items-fiscalyear
      AND   b~offsettingledgergllineitem = @lt_journal_items-ledgergllineitem
      INTO TABLE @DATA(lt_itemtext).
      SORT lt_itemtext BY companycode accountingdocument fiscalyear offsettingledgergllineitem.
      LOOP AT lt_journal_items ASSIGNING FIELD-SYMBOL(<fs_text>).
        READ TABLE lt_itemtext INTO DATA(ls_itemtext) WITH KEY companycode = <fs_text>-companycode
                                                               accountingdocument = <fs_text>-accountingdocument
                                                               fiscalyear =  <fs_text>-fiscalyear
                                                               offsettingledgergllineitem = <fs_text>-ledgergllineitem BINARY SEARCH.
        IF sy-subrc = 0.
          IF ls_itemtext-documentitemtext IS NOT INITIAL.
            <fs_text>-documentitemtext = ls_itemtext-documentitemtext.
          ELSE.
            <fs_text>-documentitemtext = ls_itemtext-accountingdocumentheadertext.
          ENDIF.
        ELSE.
          <fs_text>-documentitemtext = ''.
        ENDIF.
      ENDLOOP.
    ENDIF.
**********************************************************************
    DATA: lt_each_page TYPE tt_journal_items.
    " Process period data
    LOOP AT lt_journal_items INTO DATA(lg_journal_items)
    GROUP BY (
       companycode = lg_journal_items-companycode
       glaccount = lg_journal_items-glaccount
       supplier =  lg_journal_items-supplier
       transactioncurrency = lg_journal_items-transactioncurrency
       companycodecurrency = lg_journal_items-companycodecurrency
*    glaccount = lg_journal_items-glaccount supplier =  lg_journal_items-supplier
    )
    ASSIGNING FIELD-SYMBOL(<group>).
      " For each group, process the journal items
      LOOP AT GROUP <group> INTO DATA(ls_item).
        APPEND ls_item TO lt_each_page.
      ENDLOOP.
*      ls_result-companyname = lv_company_name.

      ls_result-companyname = ls_companycode_info-companycodename.
      ls_result-companyaddress = ls_companycode_info-companycodeaddr. "new

      ls_result-transactioncurrency = ls_item-transactioncurrency.
      ls_result-companycodecurrency = ls_item-companycodecurrency.
      lv_racct = <group>-glaccount.
      lv_partner = <group>-supplier.
      " Get opening balance
      get_opening_balance(
        EXPORTING
          iv_bukrs = lv_bukrs
          iv_racct = lv_racct
          iv_partner = lv_partner
          iv_date = lv_date_from
          iv_currency = ls_result-transactioncurrency
        IMPORTING
          ev_debit = ls_result-openingdebitbalance
          ev_credit = ls_result-openingcreditbalance
*          ev_balance = ls_result-openingbalance
          ev_debit_tran = ls_result-openingdebitbalancetran
          ev_credit_tran = ls_result-openingcreditbalancetran
*          ev_balance_tran = ls_result-OpeningBalanceTran
          ).
*      IF ls_currency-low IS INITIAL.
*        ls_result-transactioncurrency = 'USD'.
*      ENDIF.
      process_period_data(
          EXPORTING
            it_journal_items = lt_each_page
            iv_bukrs = lv_bukrs
            iv_racct = lv_racct
            iv_partner = lv_partner
            iv_date_from = lv_date_from
            iv_date_to = lv_date_to
            iv_currency = ls_result-transactioncurrency
          IMPORTING
            et_line_items = lt_line_items
            ev_debit_total = ls_result-debitamountduringperiod
            ev_credit_total = ls_result-creditamountduringperiod
            ev_debit_total_tran = ls_result-debitamountduringperiodtran
            ev_credit_total_tran = ls_result-creditamountduringperiodtran

      ).
      " Nếu tran curency = 'VND', bỏ tran amount chỉ lấy company amount.
      LOOP AT lt_line_items ASSIGNING FIELD-SYMBOL(<fs_line_items>).
        IF ls_result-transactioncurrency = 'VND' OR ls_currency-low = 'VND' OR ( ls_currency-low = '' AND <fs_line_items>-transactioncurrency NE 'USD' ).
          CLEAR:
          <fs_line_items>-debit_amount_tran,
          <fs_line_items>-credit_amount_tran,
          <fs_line_items>-balance_tran,
          <fs_line_items>-closingcredit_tran,
          <fs_line_items>-closingdebit_tran.
        ENDIF.
      ENDLOOP.
      " Logic chung tu clear.
*      lt_line_items_tmp = lt_line_items.
*      LOOP AT lt_line_items INTO DATA(ls_line_item).
*        IF ls_line_item-debit_amount IS NOT INITIAL.
*          READ TABLE lt_line_items_tmp INTO DATA(ls_line_items_tmp) WITH KEY document_number = ls_line_item-document_number
*                                                                             credit_amount  = ls_line_item-debit_amount.
*          IF sy-subrc = 0.
*            DELETE lt_line_items WHERE document_number = ls_line_items_tmp-document_number.
*          ENDIF.
*
*        ELSEIF ls_line_item-credit_amount IS NOT INITIAL.
*          READ TABLE lt_line_items_tmp INTO DATA(ls_line_items_tmp_cre) WITH KEY document_number = ls_line_item-document_number
*                                                                             debit_amount  = ls_line_item-credit_amount.
*          IF sy-subrc = 0.
*            DELETE lt_line_items WHERE document_number = ls_line_items_tmp_cre-document_number.
*          ENDIF.
*        ENDIF.
*      ENDLOOP.
      " Convert line items to JSON
      ls_result-lineitemsjson = convert_line_items_to_json( lt_line_items ).
      IF lt_line_items IS INITIAL.
        ls_result-itemdataflag = 'X'.
      ENDIF.

      " Calculate closing balance based on account nature
      DATA(lv_account_nature) = determine_account_nature( lv_racct ).

*      IF lv_account_nature = 'D'. " Debit nature accounts
*        ls_result-closingbalance = ls_result-openingbalance +
*                                   ls_result-debitamountduringperiod -
*                                   ls_result-creditamountduringperiod.
*      ELSE. " Credit nature accounts
*        ls_result-closingbalance = ls_result-openingbalance +
*                                   ls_result-creditamountduringperiod -
*                                   ls_result-debitamountduringperiod.
*      ENDIF.
      lv_closing = ls_result-openingdebitbalance - ls_result-openingcreditbalance +
          ls_result-debitamountduringperiod - ls_result-creditamountduringperiod.
      IF lv_closing < 0.
        ls_result-closingcredit = lv_closing * -1.
      ELSE.
        ls_result-closingdebit = lv_closing.
      ENDIF.
      CLEAR lv_closing.
      " Calculate closing balance in transaction currency
      lv_closing = ls_result-openingdebitbalancetran - ls_result-openingcreditbalancetran +
          ls_result-debitamountduringperiodtran - ls_result-creditamountduringperiodtran.
      IF lv_closing < 0.
        ls_result-closingcredittran = lv_closing * -1.
      ELSE.
        ls_result-closingdebittran = lv_closing.
      ENDIF.

      " Set key fields
      ls_result-companycode = lv_bukrs.
      ls_result-glaccountnumber = lv_racct.
      ls_result-businesspartner = lv_partner.
      ls_result-postingdatefrom = lv_date_from.
      ls_result-postingdateto = lv_date_to.
      " Get business partner name
      ls_result-businesspartnername = get_business_partner_name( lv_partner ).

      APPEND ls_result TO lt_result.
      CLEAR: lt_each_page, lt_line_items, ls_result.
    ENDLOOP.
********************************************************************** Them line khong phat sinh trong ky ma co o ky truoc
    LOOP AT lt_result INTO ls_result.
      READ TABLE lt_journal_items_kps INTO DATA(ls_check) WITH KEY supplier = ls_result-businesspartner
                                                                   glaccount = ls_result-glaccountnumber.
      IF sy-subrc = 0.
        DELETE lt_journal_items_kps WHERE supplier = ls_result-businesspartner AND glaccount = ls_result-glaccountnumber.
      ENDIF.
    ENDLOOP.
    " Them line
    CLEAR : ls_result.
    LOOP AT lt_journal_items_kps INTO DATA(lg_journal_items_kps)
      GROUP BY (
        companycode = lg_journal_items-companycode
        glaccount = lg_journal_items-glaccount
        supplier =  lg_journal_items-supplier
        transactioncurrency = lg_journal_items-transactioncurrency
        companycodecurrency = lg_journal_items-companycodecurrency
*      glaccount = lg_journal_items_kps-glaccount supplier =  lg_journal_items_kps-supplier
       )
      ASSIGNING FIELD-SYMBOL(<group_kps>).
      " For each group, process the journal items
      LOOP AT GROUP <group_kps> INTO DATA(ls_item_kps).
        APPEND ls_item_kps TO lt_each_page.
      ENDLOOP.
*      ls_result-companyname = lv_company_name.

      ls_result-companyname = ls_companycode_info-companycodename.
      ls_result-companyaddress = ls_companycode_info-companycodeaddr. "new

      ls_result-transactioncurrency = ls_item_kps-transactioncurrency.
      ls_result-companycodecurrency = ls_item_kps-companycodecurrency.
      lv_racct = <group_kps>-glaccount.
      lv_partner = <group_kps>-supplier.
      " Get opening balance
      get_opening_balance(
        EXPORTING
          iv_bukrs = lv_bukrs
          iv_racct = lv_racct
          iv_partner = lv_partner
          iv_date = lv_date_from
          iv_currency = ls_result-transactioncurrency
        IMPORTING
          ev_debit = ls_result-openingdebitbalance
          ev_credit = ls_result-openingcreditbalance
          ev_debit_tran = ls_result-openingdebitbalancetran
          ev_credit_tran = ls_result-openingcreditbalancetran
          ).
*      IF ls_currency-low IS INITIAL.
*        ls_result-transactioncurrency = 'USD'.
*      ENDIF.
      " Calculate closing balance based on account nature
      DATA(lv_account_nature_kps) = determine_account_nature( lv_racct ).
      lv_closing = ls_result-openingdebitbalance - ls_result-openingcreditbalance +
          ls_result-debitamountduringperiod - ls_result-creditamountduringperiod.
      IF lv_closing < 0.
        ls_result-closingcredit = lv_closing * -1.
      ELSE.
        ls_result-closingdebit = lv_closing.
      ENDIF.
      CLEAR lv_closing.
      " Set key fields
      ls_result-companycode = lv_bukrs.
      ls_result-glaccountnumber = lv_racct.
      ls_result-businesspartner = lv_partner.
      ls_result-postingdatefrom = lv_date_from.
      ls_result-postingdateto = lv_date_to.
      " Get business partner name
      ls_result-businesspartnername = get_business_partner_name( lv_partner ).

      APPEND ls_result TO lt_result_kps.
      CLEAR: lt_each_page, lt_line_items, ls_result.
    ENDLOOP.
    APPEND LINES OF lt_result_kps TO lt_result.
    DELETE lt_result WHERE creditamountduringperiod = 0 AND debitamountduringperiod = 0
    AND creditamountduringperiodtran = 0 AND debitamountduringperiodtran = 0
    AND openingcreditbalance = 0 AND openingdebitbalance = 0 AND itemdataflag = 'X'.

**********************************************************************
    " Nếu tran curency = 'VND', bỏ tran amount chỉ lấy company amount.
    LOOP AT lt_result ASSIGNING FIELD-SYMBOL(<fs_result>).
      IF <fs_result>-transactioncurrency = 'VND' OR ls_currency-low = 'VND' OR ( ls_currency-low = '' AND <fs_result>-transactioncurrency NE 'USD' ).
        CLEAR:
        <fs_result>-openingcreditbalancetran,
        <fs_result>-openingdebitbalancetran,
        <fs_result>-creditamountduringperiodtran,
        <fs_result>-debitamountduringperiodtran,
        <fs_result>-closingcredittran,
        <fs_result>-closingdebittran.
      ENDIF.
    ENDLOOP.
    " 4. Sorting
    DATA(sort_order) = VALUE abap_sortorder_tab(
      FOR sort_element IN io_request->get_sort_elements( )
      ( name = sort_element-element_name descending = sort_element-descending ) ).
    IF sort_order IS NOT INITIAL.
      SORT lt_result BY (sort_order).
    ENDIF.
**********************************************************************
    DATA: ls_page_info      TYPE zcl_get_filter_ar_sum=>ty_page_info.
    DATA(lo_common_app) = zcl_get_filter_ar_sum=>get_instance( ).

    "  LẤY FILTER TỪ UI (CompanyCode, PostingDate, ...)
*        zcl_get_filter_bangkevat=>get_instance( )->get_fillter_app(
    lo_common_app->get_fillter_app(
      EXPORTING
        io_request   = io_request
        io_response  = io_response
      IMPORTING
        wa_page_info     = ls_page_info
    ).
    " 7. Apply paging
    DATA(max_rows) = COND #( WHEN ls_page_info-page_size = if_rap_query_paging=>page_size_unlimited THEN 0
           ELSE ls_page_info-page_size ).

    max_rows = ls_page_info-page_size + ls_page_info-offset.

    LOOP AT lt_result INTO ls_result.
      IF sy-tabix > ls_page_info-offset.
        IF sy-tabix > max_rows.
          EXIT.
        ELSE.
          APPEND ls_result TO lt_result1.
        ENDIF.
      ENDIF.
    ENDLOOP.

    IF io_request->is_total_numb_of_rec_requested( ).
      io_response->set_total_number_of_records( lines( lt_result ) ).
    ENDIF.

    IF io_request->is_data_requested( ).
      io_response->set_data( lt_result1 ).
    ENDIF.
*    DATA(lv_total_records) = lines( lt_result ).
*
*    DATA(lo_paging) = io_request->get_paging( ).
*    IF lo_paging IS BOUND.
*      DATA(top) = lo_paging->get_page_size( ).
*      IF top < 0. " -1 means all records
*        top = lv_total_records.
*      ENDIF.
*      DATA(skip) = lo_paging->get_offset( ).
*
*      IF skip >= lv_total_records.
*        CLEAR lt_result. " Offset is beyond the total number of records
*      ELSEIF top = 0.
*        CLEAR lt_result. " No records requested
*      ELSE.
*        " Calculate the actual range to keep
*        DATA(lv_start_index) = skip + 1. " ABAP uses 1-based indexing
*        DATA(lv_end_index) = skip + top.
*
*        " Ensure end index doesn't exceed table size
*        IF lv_end_index > lv_total_records.
*          lv_end_index = lv_total_records.
*        ENDIF.
*
*        " Create a new table with only the required records
*        DATA: lt_paged_result LIKE lt_result.
*        CLEAR lt_paged_result.
*
*        " Copy only the required records
*        DATA(lv_index) = lv_start_index.
*        WHILE lv_index <= lv_end_index.
*          APPEND lt_result[ lv_index ] TO lt_paged_result.
*          lv_index = lv_index + 1.
*        ENDWHILE.
*
*        lt_result = lt_paged_result.
*      ENDIF.
*    ENDIF.
*    " 6. Set response
*    IF io_request->is_data_requested( ).
*      io_response->set_data( lt_result ).
*    ENDIF.
*    IF io_request->is_total_numb_of_rec_requested( ).
*      io_response->set_total_number_of_records( lines( lt_result ) ).
*    ENDIF.



  ENDMETHOD.


  METHOD process_period_data.
    DATA: ls_line_item       TYPE zst_line_item_detail,
          lv_running_balance TYPE wrbtr.

    CLEAR: et_line_items, ev_debit_total, ev_credit_total.

    " Sort by date and document
    DATA(lt_journal_items) = it_journal_items.
    SORT lt_journal_items BY postingdate accountingdocument.

    DATA: lt_where_clauses TYPE TABLE OF string.

    APPEND | supplier = @iv_partner| TO lt_where_clauses.
    APPEND |AND postingdate < @iv_date_from| TO lt_where_clauses.
    APPEND |AND companycode = @iv_bukrs| TO lt_where_clauses.
    APPEND |AND ledger = '0L'| TO lt_where_clauses.
    APPEND |AND financialaccounttype = 'K'| TO lt_where_clauses.
    APPEND |AND supplier IS NOT NULL| TO lt_where_clauses.
    APPEND |AND debitcreditcode IN ('S', 'H')| TO lt_where_clauses.
    APPEND |AND glaccount = @iv_racct| TO lt_where_clauses.

    IF iv_currency IS NOT INITIAL.
      APPEND |AND transactioncurrency = @iv_currency| TO lt_where_clauses.
    ENDIF.



    SELECT supplier AS bp,
           companycode AS rbukrs,
           SUM( CASE WHEN debitcreditcode = 'S' THEN amountincompanycodecurrency ELSE 0 END ) AS open_debit,
           SUM( CASE WHEN debitcreditcode = 'H' THEN amountincompanycodecurrency ELSE 0 END ) AS open_credit,
           SUM( CASE WHEN debitcreditcode = 'S' THEN amountintransactioncurrency ELSE 0 END ) AS open_debit_tran,
           SUM( CASE WHEN debitcreditcode = 'H' THEN amountintransactioncurrency ELSE 0 END ) AS open_credit_tran,
           transactioncurrency,
           companycodecurrency,
           glaccount
      FROM i_journalentryitem
      WHERE (lt_where_clauses)
*      WHERE supplier = @iv_partner
*        AND postingdate < @iv_date_from
*        AND companycode = @iv_bukrs
*        AND ledger = '0L'
*        AND financialaccounttype = 'K'
*        AND supplier IS NOT NULL
*        AND debitcreditcode IN ('S', 'H')
*        AND glaccount = @iv_racct
*        AND transactioncurrency = @iv_currency
      GROUP BY supplier, companycode, transactioncurrency, companycodecurrency, glaccount
      INTO TABLE @DATA(lt_open_balances).
*    DATA : ls_open_balance     LIKE LINE OF lt_open_balances,
*           ls_open_balance_tmp LIKE LINE OF lt_open_balances.
    SORT lt_open_balances BY bp rbukrs.
*    LOOP AT lt_open_balances INTO DATA(ls_open_tmp) WHERE rbukrs = iv_bukrs AND bp = iv_partner.
*
*      ls_open_balance-open_debit =  ls_open_balance-open_debit + ls_open_tmp-open_debit." + ls_open_tmp-open_credit.
*      ls_open_balance-open_credit =  ls_open_balance-open_credit + ls_open_tmp-open_credit." + ls_open_tmp-open_credit.
*      ls_open_balance-companycodecurrency = ls_open_tmp-companycodecurrency.
*      IF iv_currency = ''.
*        IF ls_open_tmp-transactioncurrency = 'USD'.
*          ls_open_balance-transactioncurrency = 'USD'.
*          ls_open_balance-open_debit_tran = ls_open_balance-open_debit_tran + ls_open_tmp-open_debit_tran." + ls_open_tmp-open_credit_tran.
*          ls_open_balance-open_credit_tran = ls_open_balance-open_credit_tran + ls_open_tmp-open_credit_tran." + ls_open_tmp-open_credit_tran.
*        ENDIF.
*      ELSE.
**        ls_open_balance-open_debit =  ls_open_balance-open_debit + ls_open_tmp-open_debit." + ls_open_tmp-open_credit.
**        ls_open_balance-open_credit =  ls_open_balance-open_credit + ls_open_tmp-open_credit." + ls_open_tmp-open_credit.
*        ls_open_balance-open_debit_tran = ls_open_balance-open_debit_tran + ls_open_tmp-open_debit_tran." + ls_open_tmp-open_credit_tran.
*        ls_open_balance-open_credit_tran = ls_open_balance-open_credit_tran + ls_open_tmp-open_credit_tran." + ls_open_tmp-open_credit_tran.
*      ENDIF.
*    ENDLOOP.
*    if iv_currency
    READ TABLE lt_open_balances INTO DATA(ls_open_balance) WITH KEY bp = iv_partner rbukrs = iv_bukrs.

    " Get account nature for balance calculation
    DATA(lv_account_nature) = determine_account_nature( iv_racct ).
*    IF iv_currency IS INITIAL.
*      LOOP AT lt_journal_items ASSIGNING FIELD-SYMBOL(<fs_items>).
*        IF <fs_items>-transactioncurrency NE 'USD'.
*          CLEAR : <fs_items>-amountintransactioncurrency.
*        ENDIF.
*      ENDLOOP.
*    ENDIF.

*      lt_line_items_tmp = lt_line_items.
    " Xóa bỏ chứng từ case clear.
    DATA(lt_journal_items_tmp) = it_journal_items.
    SORT lt_journal_items_tmp BY accountingdocument accountingdocument amountincompanycodecurrency debitcreditcode amountintransactioncurrency supplier.
    LOOP AT lt_journal_items_tmp INTO DATA(ls_line_clear).
      ls_line_clear-amountincompanycodecurrency = ls_line_clear-amountincompanycodecurrency * -1.
      ls_line_clear-amountintransactioncurrency = ls_line_clear-amountintransactioncurrency * -1.
      IF ls_line_clear-amountincompanycodecurrency IS NOT INITIAL AND ls_line_clear-debitcreditcode = 'S'.
        READ TABLE lt_journal_items_tmp INTO DATA(ls_line_items_tmp) WITH KEY accountingdocument = ls_line_clear-accountingdocument
                                                                              amountincompanycodecurrency  = ls_line_clear-amountincompanycodecurrency
                                                                              debitcreditcode = 'H'
                                                                              amountintransactioncurrency = ls_line_clear-amountintransactioncurrency
                                                                              supplier = ls_line_clear-supplier BINARY SEARCH.
        IF sy-subrc = 0.
          READ TABLE lt_journal_items INTO DATA(ls_clear_h) WITH KEY accountingdocument = ls_line_clear-accountingdocument
                                               supplier = ls_line_clear-supplier
                                               amountincompanycodecurrency  = ls_line_clear-amountincompanycodecurrency
                                               amountintransactioncurrency  = ls_line_clear-amountintransactioncurrency.



          IF sy-subrc = 0.
*          DELETE lt_journal_items WHERE accountingdocument = ls_line_clear-accountingdocument
*                                    AND supplier = ls_line_clear-supplier
*                                    AND amountincompanycodecurrency  = ls_line_clear-amountincompanycodecurrency
*                                    AND amountintransactioncurrency  = ls_line_clear-amountintransactioncurrency.
            DELETE lt_journal_items INDEX sy-tabix.
          ENDIF.
        ENDIF.

      ELSEIF ls_line_clear-amountincompanycodecurrency IS NOT INITIAL AND ls_line_clear-debitcreditcode = 'H'.
        READ TABLE lt_journal_items_tmp INTO DATA(ls_line_clear_tmp) WITH KEY accountingdocument = ls_line_clear-accountingdocument
                                                                              amountincompanycodecurrency  = ls_line_clear-amountincompanycodecurrency
                                                                              debitcreditcode = 'S'
                                                                              amountintransactioncurrency = ls_line_clear-amountintransactioncurrency
                                                                              supplier = ls_line_clear-supplier BINARY SEARCH.
        IF sy-subrc = 0.
          READ TABLE lt_journal_items INTO DATA(ls_clear_s) WITH KEY accountingdocument = ls_line_clear-accountingdocument
                                       supplier = ls_line_clear-supplier
                                       amountincompanycodecurrency  = ls_line_clear-amountincompanycodecurrency
                                       amountintransactioncurrency  = ls_line_clear-amountintransactioncurrency.



          IF sy-subrc = 0.
*          DELETE lt_journal_items WHERE accountingdocument = ls_line_clear-accountingdocument
*                                    AND supplier = ls_line_clear-supplier
*                                    AND amountincompanycodecurrency  = ls_line_clear-amountincompanycodecurrency
*                                    AND amountintransactioncurrency  = ls_line_clear-amountintransactioncurrency.
            DELETE lt_journal_items INDEX sy-tabix.
          ENDIF.
        ENDIF.
      ENDIF.
    ENDLOOP.


    LOOP AT lt_journal_items INTO DATA(ls_item).
      CLEAR ls_line_item.

      ls_line_item-posting_date = ls_item-postingdate.
      ls_line_item-document_number = ls_item-accountingdocument.
      ls_line_item-document_date = ls_item-documentdate.
      ls_line_item-transactioncurrency = iv_currency.
      ls_line_item-companycodecurrency = ls_item-companycodecurrency.
      ls_line_item-profit_center = ls_item-profitcenter.


      " Get contra account
      ls_line_item-contra_account = get_contra_account(
        iv_bukrs = ls_item-companycode
        iv_accountingdoc = ls_item-accountingdocument
        iv_fiscalyear = ls_item-fiscalyear
        iv_racct = ls_item-glaccount
        iv_lineitem = ls_item-ledgergllineitem ).

      " Set text
      ls_line_item-item_text = ls_item-documentitemtext.

      " Determine debit/credit amounts
      IF ls_item-debitcreditcode = 'S'.
        ls_line_item-debit_amount = ls_item-amountincompanycodecurrency .
        ev_debit_total = ev_debit_total + ls_line_item-debit_amount.
        " transaction currency
        ls_line_item-debit_amount_tran = ls_item-amountintransactioncurrency.
        ev_debit_total_tran = ev_debit_total_tran + ls_line_item-debit_amount_tran.
      ELSE.
        ls_line_item-credit_amount = ls_item-amountincompanycodecurrency * -1.
        ev_credit_total = ev_credit_total + ls_line_item-credit_amount.
        " transaction currency
        ls_line_item-credit_amount_tran = ls_item-amountintransactioncurrency * -1.
        ev_credit_total_tran = ev_credit_total_tran + ls_line_item-credit_amount_tran.
      ENDIF.

      IF ls_open_balance-open_debit + ls_open_balance-open_credit + ev_debit_total - ev_credit_total > 0.
        ls_line_item-closingdebit = ls_open_balance-open_debit + ls_open_balance-open_credit + ev_debit_total - ev_credit_total.
        ls_line_item-closingcredit = 0.
      ELSE.
        ls_line_item-closingcredit = ( ls_open_balance-open_debit + ls_open_balance-open_credit + ev_debit_total - ev_credit_total ) * -1.
        ls_line_item-closingdebit = 0.
      ENDIF.

      " transaction currency closing amounts
      IF ls_open_balance-open_debit_tran + ls_open_balance-open_credit_tran + ev_debit_total_tran - ev_credit_total_tran > 0.
        ls_line_item-closingdebit_tran = ls_open_balance-open_debit_tran + ls_open_balance-open_credit_tran + ev_debit_total_tran - ev_credit_total_tran.
        ls_line_item-closingcredit_tran = 0.
      ELSE.
        ls_line_item-closingcredit_tran = ( ls_open_balance-open_debit_tran + ls_open_balance-open_credit_tran + ev_debit_total_tran - ev_credit_total_tran ) * -1.
        ls_line_item-closingdebit_tran = 0.
      ENDIF.
      ls_line_item-debit_amount = COND #( WHEN ls_line_item-companycodecurrency = 'VND'
                                          THEN ls_line_item-debit_amount * 100
                                          ELSE ls_line_item-debit_amount ) .
      ls_line_item-credit_amount = COND #( WHEN ls_line_item-companycodecurrency = 'VND'
                                           THEN ls_line_item-credit_amount * 100
                                           ELSE ls_line_item-credit_amount ) .
      ls_line_item-debit_amount_tran = COND #( WHEN ls_line_item-transactioncurrency = 'VND'
                                               THEN ls_line_item-debit_amount_tran * 100
                                               ELSE ls_line_item-debit_amount_tran ).
      ls_line_item-credit_amount_tran = COND #( WHEN ls_line_item-transactioncurrency = 'VND'
                                                THEN ls_line_item-credit_amount_tran * 100
                                                ELSE ls_line_item-credit_amount_tran ).
      ls_line_item-closingdebit = COND #( WHEN ls_line_item-companycodecurrency = 'VND'
                                          THEN ls_line_item-closingdebit * 100
                                          ELSE ls_line_item-closingdebit ) .
      ls_line_item-closingcredit = COND #( WHEN ls_line_item-companycodecurrency = 'VND'
                                           THEN ls_line_item-closingcredit * 100
                                           ELSE ls_line_item-closingcredit ) .
      ls_line_item-closingdebit_tran = COND #( WHEN ls_line_item-transactioncurrency = 'VND'
                                               THEN ls_line_item-closingdebit_tran * 100
                                               ELSE ls_line_item-closingdebit_tran ).
      ls_line_item-closingcredit_tran = COND #( WHEN ls_line_item-transactioncurrency = 'VND'
                                                THEN ls_line_item-closingcredit_tran * 100
                                                ELSE ls_line_item-closingcredit_tran ).
      APPEND ls_line_item TO et_line_items.
    ENDLOOP.

  ENDMETHOD.
ENDCLASS.
