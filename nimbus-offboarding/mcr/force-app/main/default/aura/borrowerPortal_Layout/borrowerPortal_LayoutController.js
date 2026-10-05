/**
 * Created by zeyad on 7/15/2024.
 */

({
  doInit: function (component, event, helper) {
    const root = document.querySelector(':root');
    root.style.setProperty(
      '--pulse-primary-gradient',
      'linear-gradient(0deg, ' + component.get('v.primaryGradientColor') + ' 0%, ' + component.get('v.secondaryGradientColor') + ' 100%)'
    );
    component.set('v.isLoaded', true);
  },
  menuItemClicked: function (component, event, helper) {
    const id = event.target.dataset.menuItemId;
    if (id) {
      component.getSuper().navigate(id);
    }
  }
});