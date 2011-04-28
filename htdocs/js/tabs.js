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
  function(tabname,animate) {
      this.do_select_tab(tabname+'_select',animate);
  },

  do_select_tab:
  function(tab_id,animate) {
      if (animate==null) animate=true;
      var whichOne;
      for (var i=0;i<this.tab_menus.length;i++) {
	  if (this.tab_menus[i].id == tab_id)
	      whichOne=i;
      }
      var current = this.tab_divs.find(function (e) { 
	      return e.visible();
	  });
      
      var imgs           = document.getElementsByClassName('toolbarStar');
      var stars_id_array = idtoarray(imgs,'toolbarStar');
      this.tab_menus.each(
			  function(e) {
			      e.className='tabmenu_inactive';
			  });
      this.tab_menus[whichOne].className='tabmenu_active';
      var  tab = this.tab_divs[whichOne];
	  
      if (current != null) current.hide();
      if (animate)
	  new Effect.BlindDown( this.tab_divs[whichOne],{ 
			  queue:      'front',
			  duration:    0.5,
			  afterFinish: function() { onTabLoad(tab_id); 
			  }
	  });
      else
	  this.tab_divs[whichOne].show();
  }

});  // end Class.create
