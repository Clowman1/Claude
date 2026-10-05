/**
 * Created by zeyad on 6/26/2020.
 */
({
    calculateEndOfMonth : function(fields){
        let date = new Date(fields.Settlement_Time_for_Wire__c);
        return new Date(date.getFullYear(), date.getMonth() + 1, 0);
    },
    // ? :) 
    calculateBank_Funded__c : function(fields) {
        return parseFloat(fields.Amount_Bank_Funded__c)/parseFloat(fields.Loan_Amount__c)*100;
    },
    calculateAmount_Bank_Funded__c : function(fields) {
        const bankFunded = parseFloat(fields.Bank_Funded__c) / 100;
        console.log(bankFunded);
        return (parseFloat(fields.Amount_To_Be_Funded__c) < /*.99*/ bankFunded * parseFloat(fields.Loan_Amount__c)) ? parseFloat(fields.Amount_To_Be_Funded__c) : /*.99*/ bankFunded * parseFloat(fields.Loan_Amount__c);
    },
    calculateHaircut__c : function(fields) {
        const bankFunded = parseFloat(fields.Bank_Funded__c) / 100;
        return (parseFloat(fields.Amount_To_Be_Funded__c) - parseFloat(fields.Amount_Bank_Funded__c)) < 0 ? (parseFloat(fields.Loan_Amount__c)*(1 - parseFloat(/*.99*/ bankFunded))) : parseFloat(fields.Amount_To_Be_Funded__c) - parseFloat(fields.Amount_Bank_Funded__c);
    },
    calculatePer_Diem__c : function(fields){
        return (parseFloat(fields.Loan_Amount__c) * parseFloat(fields.Interest_Rate__c/100))/365;
    },
    calculateDisbursement_Day__c : function(fields){
        return new Date(fields.Settlement_Time_for_Wire__c).getDate();
    },
    calculatePPD_Interest_Days__c : function(fields){
        return (fields.PPD_Interest_Type__c === "Interest Expense") ?  new Date(fields.EOMONTH__c).getDate()+1 - (new Date(fields.Settlement_Time_for_Wire__c).getDate()- 1) : (fields.Disbursement_Day__c - 1);
    },
    calculatePPD_Interest__c : function(fields){
        let ppdInterest = parseFloat(fields.Per_Diem__c) * parseFloat(fields.PPD_Interest_Days__c);
        return ppdInterest;
        //console.log(fields.PPD_Interest_Type__c);
        //return (fields.PPD_Interest_Type__c === "Interest Expense") ? ppdInterest : -1*ppdInterest;
    },
    calculateAmount_To_Be_Funded__c : function(fields){
/*        console.log(
    "Loan Amount:", fields.Loan_Amount__c,
    " + Lender Credit:", fields.Lender_Credit__c,
    " - (Origination:", fields.Origination_Charges__c,
    " + Escrow:", fields.Escrow_Total__c,
    " + Appraisal:", fields.Appraisal_Cost__c,
    " + Credit Report:", fields.Credit_Report_Fee__c,
    " + Flood Cert:", fields.Flood_Cert__c,
    " + VA/FHA Funding:", fields.VA_FHA_Funding_Fee__c,
    " + Warehouse:", fields.Warehouse_Fee__c,
    " + MERS:", fields.MERS_Fee__c,
    " + Tax Service:", fields.Tax_Service_Fee__c,
    ") - PPD Interest:", fields.PPD_Interest__c
);

console.log("Calculated Amount:",
    parseFloat(fields.Loan_Amount__c) -
    (
        -parseFloat(fields.Lender_Credit__c) +
        parseFloat(fields.Origination_Charges__c) +
        parseFloat(fields.Escrow_Total__c) +
        parseFloat(fields.Appraisal_Cost__c) +
        parseFloat(fields.Credit_Report_Fee__c) +
        parseFloat(fields.Flood_Cert__c) +
        parseFloat(fields.VA_FHA_Funding_Fee__c) +
        parseFloat(fields.Warehouse_Fee__c) +
        parseFloat(fields.MERS_Fee__c) +
        parseFloat(fields.Tax_Service_Fee__c)
    ) -
    fields.PPD_Interest__c
);*/
        const ppdInterestAmount = 
            (fields.PPD_Interest_Type__c === "Interest Expense")
                ? parseFloat(fields.PPD_Interest__c)
                : -1 * parseFloat(fields.PPD_Interest__c);
        
        console.log('PPD Interest', ppdInterestAmount);
        return parseFloat(fields.Loan_Amount__c) -
            (-parseFloat(fields.Lender_Credit__c) 
             + parseFloat(fields.Origination_Charges__c) 
             + parseFloat(fields.Escrow_Total__c) 
             + parseFloat(fields.Appraisal_Cost__c ) 
             + parseFloat(fields.Credit_Report_Fee__c) 
             + parseFloat(fields.Flood_Cert__c) 
             + parseFloat(fields.VA_FHA_Funding_Fee__c) 
             + parseFloat(fields.Warehouse_Fee__c) 
             + parseFloat(fields.MERS_Fee__c) 
             + parseFloat(fields.Tax_Service_Fee__c))
        - ppdInterestAmount;
    },
    calculateWarehouse_Max_Fund__c : function(fields){
        return .99;
    }
})