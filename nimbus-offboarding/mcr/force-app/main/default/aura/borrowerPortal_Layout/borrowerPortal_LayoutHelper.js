/**
 * Created by zeyad on 7/15/2024.
 */

({
  getJsonFromUrl: function () {
    const query = location.search.substr(1);
    const result = {};
    query.split('&').forEach(function (part) {
      const item = part.split('=');
      result[item[0]] = decodeURIComponent(item[1]);
    });
    return result;
  },
  setCookie: function (cname, cvalue, exdays) {
    if (cvalue == null) {
      return;
    }
    window.sessionStorage.setItem(cname, cvalue);
  },
  getListOfCookies: function (c, name) {
    return window.sessionStorage.getItem(name);
  }
});