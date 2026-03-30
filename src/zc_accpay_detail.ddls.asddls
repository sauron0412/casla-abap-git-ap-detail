@EndUserText.label: 'GL Account Partner Ledger'
@ObjectModel.query.implementedBy: 'ABAP:ZCL_ACCPAY_DETAIL'
@Metadata.allowExtensions: true
define custom entity ZC_ACCPAY_DETAIL
{
      @Consumption.filter          : { mandatory: true, multipleSelections: false }
  key CompanyCode                  : bukrs;
      @Consumption.filter          : { mandatory: false, multipleSelections: true }
  key GLAccountNumber              : saknr;
  key BusinessPartner              : text10;
  key ProfitCenter                 : prctr;
      @Consumption.filter          : { mandatory: true, multipleSelections: false }
  key PostingDateFrom              : budat;
      @Consumption.filter          : { mandatory: true, multipleSelections: false }
  key PostingDateTo                : budat;
      @Consumption.filter          : { multipleSelections: true }
  key RHCUR                        : abap.cuky; // transaction Currency
  key TransactionCurrency          : waers;
  key CompanyCodeCurrency          : waers;
      CompanyName                  : abap.char(100);
      CompanyAddress               : abap.char(256);
      BusinessPartnerName          : abap.char(100);

      // Opening balances (before period)
      @Semantics.amount.currencyCode:'TransactionCurrency'
      OpeningDebitBalanceTran      : abap.curr(23,2);
      @Semantics.amount.currencyCode:'CompanyCodeCurrency'
      OpeningDebitBalance          : abap.curr(23,2);

      @Semantics.amount.currencyCode:'TransactionCurrency'
      OpeningCreditBalanceTran     : abap.curr(23,2);
      @Semantics.amount.currencyCode:'CompanyCodeCurrency'
      OpeningCreditBalance         : abap.curr(23,2);

      //      @Semantics.amount.currencyCode:'TransactionCurrency'
      //      OpeningBalanceTran           : abap.curr(23,2);
      //      @Semantics.amount.currencyCode:'CompanyCodeCurrency'
      //      OpeningBalance               : abap.curr(23,2);

      // Period totals
      @Semantics.amount.currencyCode:'TransactionCurrency'
      DebitAmountDuringPeriodTran  : abap.curr(23,2);
      @Semantics.amount.currencyCode:'CompanyCodeCurrency'
      DebitAmountDuringPeriod      : abap.curr(23,2);

      @Semantics.amount.currencyCode:'TransactionCurrency'
      CreditAmountDuringPeriodTran : abap.curr(23,2);
      @Semantics.amount.currencyCode:'CompanyCodeCurrency'
      CreditAmountDuringPeriod     : abap.curr(23,2);

      // Closing balance
      //      @Semantics.amount.currencyCode:'TransactionCurrency'
      //      ClosingBalanceTran           : abap.curr(23,2);
      //      @Semantics.amount.currencyCode:'CompanyCodeCurrency'
      //      ClosingBalance               : abap.curr(23,2);
      // Closing debit balance
      @Semantics.amount.currencyCode:'TransactionCurrency'
      ClosingDebitTran             : abap.curr(23,2);
      @Semantics.amount.currencyCode:'CompanyCodeCurrency'
      ClosingDebit                 : abap.curr(23,2);
      // Closing credit balance
      @Semantics.amount.currencyCode:'TransactionCurrency'
      ClosingCreditTran            : abap.curr(23,2);
      @Semantics.amount.currencyCode:'CompanyCodeCurrency'
      ClosingCredit                : abap.curr(23,2);
      //      @Consumption.filter          : { mandatory: true, multipleSelections: false }
      //      TransactionCurrency          : waers;
      //      CompanyCodeCurrency          : waers;

      // Line items as JSON string (workaround for structure limitation)
      LineItemsJson                : abap.string;
      ItemDataFlag                 : abap.char(1);
}
