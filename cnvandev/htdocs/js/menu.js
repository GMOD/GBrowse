// $Id$

var PopupMenu = Class.create( {
    initialize:
    function (title,options) {
      var d = document.createElement('DIV');
      d.innerHTML  = title;
      d.innerHTML += "<br>item1<br>item2<br>item3";
      d.setStyle({position: 'absolute',outline: 'black outset 2px'});
      d.hide();
      this.contents = d;
    },

    popUp:
    function (event) {
    	var d  = this.contents;
        d.setStyle({left:event.pointerX,top:event.pointerY});
	d.show();
    }
}