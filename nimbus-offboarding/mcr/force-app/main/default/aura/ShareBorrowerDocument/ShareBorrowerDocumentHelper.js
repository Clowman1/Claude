({
    replaceLinks : function(component) {
        let htmlBody = component.get("v.htmlBody");
        let distributions = component.get("v.distributions");
        
        if (!htmlBody || !distributions || distributions.length === 0) {
            console.warn("No htmlBody or distributions available");
            return;
        }
        
        console.log(JSON.stringify(distributions));
        
        // Creating an unordered list of links
        let linksList = "<ul>" + 
            distributions.map(dist => `<li><a href="${dist.DistributionPublicUrl}">${dist.Name}</a> - Document Password: <b>${dist.Password}</b></li>`).join("") 
        + "</ul>";
        
        // Replacing the placeholder
        htmlBody = htmlBody.replace(/\{LinksToInsert\}/g, linksList);
        
        // Setting the modified HTML body back to the component
        component.set("v.htmlBody", htmlBody);
    }
})