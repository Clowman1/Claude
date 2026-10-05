/**
 * Created by Zeyad Jabra on 8/18/2019.
 */
({
    calculateSummaryRow : function(currentState,datapoint){
        let datapointToSummaryPointMap = new Map([
            ['AC066', ['AC010', 'AC020', '-AC030', '-AC040','-AC050', '-AC060', '-AC062', '-AC064', 'AC065']],
            ['AC090', ['AC070', 'AC080']],
            ['AC190', ['AC100', 'AC110', 'AC120', 'AC130']],
            ['AC290', ['AC200', 'AC210', 'AC220']],
            ['AC390', ['AC300', 'AC310', 'AC320']],
            ['AC590', ['AC500', 'AC510', 'AC520']],
            ['AC790', ['AC700', 'AC710', 'AC720']],
            ['AC890', ['AC800', 'AC810']],
            ['AC990', ['AC920', 'AC930', 'AC940']]
        ]);
        let baseProperty = datapoint.split('.')[0];
        let datapointName = datapoint.split('.')[2];
        let pointsToSum = datapointToSummaryPointMap.get(datapointName);
        let count = 0, amount = 0, corrCount = 0, corrAmount = 0;
        for(let point of pointsToSum){
            if(point.indexOf('-')==0){
                let tempAmount =currentState[baseProperty][point.substring(1, point.length)+'_1'];
                let tempCount = currentState[baseProperty][point.substring(1, point.length)+'_2'];
                let tempCorrAmount =currentState[baseProperty][point.substring(1, point.length)+'_3'];
                let tempCorrCount = currentState[baseProperty][point.substring(1, point.length)+'_4'];
                amount -= (isNaN(tempAmount) ?  0 : tempAmount);
                count -= (isNaN(tempCount) ?  0 : tempCount);
                corrAmount -= (isNaN(tempCorrAmount) ?  0 : tempCorrAmount);
                corrCount -= (isNaN(tempCorrCount) ?  0 : tempCorrCount);
            }else{
                let tempAmount =currentState[baseProperty][point+'_1'];
                let tempCount = currentState[baseProperty][point+'_2'];
                let tempCorrAmount =currentState[baseProperty][point+'_3'];
                let tempCorrCount = currentState[baseProperty][point+'_4'];
                amount += (isNaN(tempAmount) ?  0 : tempAmount);
                count += (isNaN(tempCount) ?  0 : tempCount);
                corrAmount += (isNaN(tempCorrAmount) ?  0 : tempCorrAmount);
                corrCount += (isNaN(tempCorrCount) ?  0 : tempCorrCount);
            }
        }
        currentState[baseProperty][datapointName + '_1'] = amount;
        currentState[baseProperty][datapointName + '_2'] = count;
        currentState[baseProperty][datapointName + '_3'] = corrAmount;
        currentState[baseProperty][datapointName + '_4'] = corrCount;
        if(!isNaN(count) && count > 0) {
            let avg = amount / count;
            currentState[baseProperty][datapointName + '_SUM_1_2'] = avg;
        }
        
        if(!isNaN(corrCount) && corrCount) {
            let corrAvg = corrAmount / corrCount;
            currentState[baseProperty][datapointName + '_SUM_3_4'] = corrAvg;
        }
        return currentState;
    },
    showToast : function(title, message, type) {
        let toastEvent = $A.get("e.force:showToast");
        toastEvent.setParams({
            "title": title,
            "message": message,
            "type": type
        });
        toastEvent.fire();
    }
})