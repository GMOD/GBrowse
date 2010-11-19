// $Id$

var TabbedSection = Class.create( {

    initialize:
    function (tabs,initial) {
       if (initial==null) initial = 0;
       this.tab_divs  = tabs.map(function(e) { return $(e) });
       this.tab_menus = tabs.map(function(e) { return $(e+'_select') });
       for (var i=0;i<tabs.length;i++) {
          if (i != initial) this.tab_divs[i].hide();
	  Event.observe(this.tab_menus[i],
	                'click',
			this.select_tab_event.bindAsEventListener(this));
	  this.tab_menus[i].className =
                      i==initial ? 'tabmenu_active' : 'tabmenu_inactive';
       }
    },

    select_tab_event:
    function(event) {
        var menu = Event.element(event);
	var id   = menu.id;
        this.do_select_tab(id);
  },

  select_tab:
  function(tabname) {
     this.do_select_tab(tabname+'_select');
  },

  do_select_tab:
  function(tab_id) {
	  var whichOne;
	  for (var i=0;i<this.tab_menus.length;i++) {
	      if (this.tab_menus[i].id == tab_id)
	      	 whichOne=i;
          }
	  var current = this.tab_divs.find(function (e) { 
                                                 return e.visible();
                                               });

	  this.tab_menus.each(
	         function(e) {
	         	       e.className='tabmenu_inactive';
		         });
          this.tab_menus[whichOne].className='tabmenu_active';

	  if (current != null) current.hide();
	  Effect.BlindDown( this.tab_divs[whichOne],
	                    { duration: 0.5,
	                      afterFinish: function() { onTabLoad(tab_id) }
	                    }
	  );
	}

});  // end Class.create
