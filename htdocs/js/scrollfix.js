//Scrollfix - Sticks a selected element in the website to the top of the page once it has been scrolled out of view. This code is based on an original design on www.perldocs.org.
var scrollfix = {
	// state - holds the current positioning state (fixed or static)
	state: "static",
	
	// scrollfix.element_id - the id of the element to exhibit the scrollfix behaviour.
	element_id: "track_filterform",

	// The heights and vertical offsets of the scrollfix, to be set in scrollfix.setup().
	size: new Array(0, 0),
	offset: new Array(0, 0),

	// setup - initialises the window.onscroll handler
	setup: function() {
        // Calculate & set the dimensions.
        scrollfix.setDims();

        // If an internal link was called externally (not through an anchor but an address like x.html#y), the link position will be behind the scrollfix element so the page needs to be scrolled down accordingly.
        var anchor = scrollfix.internalCheck(window.location);
        if (anchor) {
            var allLinks = $$('a');
            allLinks.each(function(link) {
                if (link.readAttribute('name') == anchor) {
	                window.scrollBy(0, (link.offsetTop + scrollfix.size['height']));
                }
            });
        }

        $('stickySearch').checked = true;

        // Fix all the links (see scrollfix.rewriteLinks() for details).
        scrollfix.rewriteLinks();

        //Attach the events for the window scrolling or resizing.
        Event.observe(window, 'scroll', scrollfix.checkState);
        Event.observe(window, 'resize', scrollfix.setDims);
          
        //Remove the scroller when the checkbox is unchecked.
        Event.observe($('stickySearch'), 'click', scrollfix.checkState);
	},

	// setDims - initializes the dimensions of the scrollfix element.
	setDims: function() {
		// Reset the fixed scroller to its original position
		if ($('placeholder') != null)
			$('placeholder').remove();
		
		//Initialize the behaviour
		scrollfix.scroll();
		
		$(scrollfix.element_id).setStyle("width: 100%;"); // **** Change this to whatever the style is specified in the CSS file.
		/* This is here because Prototype getDimension functions only return computed (pixel) values, which screws up
		if the CSS file specifies flexible values (like 70%). A better idea would be getting the original CSS-
		specified value (like JQuery's css() function - http://api.jquery.com/css/) for width/height/margins, then
		applying them here. */
		
		// Recalculate that original position
		scrollfix.size = $(scrollfix.element_id).getDimensions();
		scrollfix.offset["left"] = $(scrollfix.element_id).cumulativeOffset()["left"];
		if (scrollfix.state == "static")
		  scrollfix.offset["top"] = $(scrollfix.element_id).cumulativeOffset()["top"];
    
		// Add the invisible placeholder div, and hide it
		if ($('placeholder') == null) {
      		$(scrollfix.element_id).parentNode.insertBefore( new Element('div', {'id': 'placeholder'}), $(scrollfix.element_id) );  //Prototype's insert function is buggy in IE7.
	      	$('placeholder').setStyle("margin-left: " + $(scrollfix.element_id).getStyle('margin-left'));	//This is the "internal margin", not the total offset, hence the getStyle.
	    }
	  
		$('placeholder').hide();
		scrollfix.checkState();
	},

	// checkState - checks the scroll position and updates the scrollfix element.
	checkState: function() {
		var currentScroll = document.viewport.getScrollOffsets();
		
		if ($('stickySearch').checked == true) {
		  // If the scrollfix's static and should be fixed (the user has scrolled down), change it.
		  if ((scrollfix.state == 'static') && (currentScroll['top'] > scrollfix.offset['top'])) {
		    scrollfix.stick();
		  }
		
		  // If the scrollfix's fixed and should be static (the user has scrolled up), change it.
		  if ((scrollfix.state == 'fixed') && (currentScroll['top'] <= scrollfix.offset['top']))
		    scrollfix.scroll();
		} else
		  scrollfix.scroll();
	},
	
  // scroll - Changes the scrollfix element to normal behaviour, scrolling with the page.	
	scroll: function() {
        $(scrollfix.element_id).setStyle("position: static;");
        scrollfix.state = 'static';
        if ($('placeholder') != null)
            $('placeholder').hide();
	},
	
	// stick - Changes the scrollfix element to fixed behavior, sticking to the top of the page.
	stick: function() {
	  //Set the background colour so that you don't have elements floating randomly in the screen if your background is transparent.
	  $(scrollfix.element_id).setStyle("background-color: " + $$('.searchtitle')[0].getStyle("background-color") + ";");
	  $(scrollfix.element_id).setStyle("position: fixed; top: 0px;");
	  $(scrollfix.element_id).setStyle("left: " + scrollfix.offset['left'] + "px;");
	  $(scrollfix.element_id).setStyle("width: " + scrollfix.size['width'] + "px;");
	  $('placeholder').show();
	  $('placeholder').setStyle("height: " + scrollfix.size['height'] + "px;");
	  scrollfix.state = 'fixed';
	},
	
	// internalCheck - Thoroughly checks if a link is internal to a document.
  internalCheck: function(link) {
	  if ((link.href && link.href.indexOf('#') != -1) && ((link.pathname == location.pathname) || ('/'+link.pathname == location.pathname)) && (link.search == location.search))
		  return link.hash.substr(1);
  },

  // needsScrolling - determines if the destination of an internal link is lower than the scrollfix element.
  needsScrolling: function(link) {
	  if (scrollfix.findInternalDestination(link).offsetTop > (scrollfix.offset['top'] + scrollfix.size['height']))
		  return true;
  },

  // findInternalDestination - Finds the internal destination of a specified link and returns it.
  findInternalDestination: function(link) {
	  // Find the <a name> tag corresponding to this href. First strip off the hash (first character).
	  anchor = link.hash.substr(1);
	  var allLinks = $$('a');
	  var destinationLink = null;

	  // Now loop all A tags until we find one with that name, and return it.
	  allLinks.each ( function(link) {
		  if (link.name && (link.name == anchor))
			  destinationLink = link;
	  });
	  return destinationLink;
  },

	// rewriteLinks - stop internal links appearing behind the scrollfix. Based on code written by Stuart Langridge - http://www.kryogenix.org
	rewriteLinks: function() {
		// Get a list of all links in the page
		var allLinks = $$('a');

		// Walk through the list, if the link is internal to the page then attach the smoothScroll function as an onclick event handler.
		allLinks.each( function(link) {
			if (scrollfix.internalCheck(link) && scrollfix.needsScrolling(link)) {
				Event.observe(link, 'click', scrollfix.linkScroll);
			}
		}); 
	},

	// linkScroll - follow internal link and scroll the page. Based on code written by Stuart Langridge - http://www.kryogenix.org
	linkScroll: function(e) {
		// This is an event handler; get the clicked on element in a cross-browser fashion.
		if (window.event)
			target = window.event.srcElement;
		else if (e)
			target = e.target;
		else return;

		// Make sure that the target is an element, not a text node within an element.
		if (target.nodeType == 3)
			target = target.parentNode;

		// Paranoia; check this is an A tag
		if (target.nodeName.toLowerCase() != 'a')
			return;

		// Find the <a name> tag corresponding to this href. First strip off the hash (first character), then loop all A tags until we find one with that name.
		anchor = target.hash.substr(1);
		var allLinks = $$('a');
		var destinationLink = null;

		allLinks.each ( function(link) {
			if (link.name && (link.name == anchor))
				destinationLink = link;
		});

		if (!destinationLink)
			destinationLink = $(anchor);

		// If we didn't find a destination, give up and let the browser do its thing.
		if (!destinationLink)
			return true;
		
		// Find the destination's position
		var destx = destinationLink.offsetLeft;   
		var desty = destinationLink.offsetTop;  
		var thisNode = destinationLink;  
		while (thisNode.offsetParent && (thisNode.offsetParent != document.body)) {  
			thisNode = thisNode.offsetParent;  
			destx += thisNode.offsetLeft;  
			desty += thisNode.offsetTop;  
		}

		// Follow the link    
		location.hash = anchor;

		// Scroll if necessary to avoid the top nav bar
		if ((window.pageYOffset > scrollfix.offset['top']) && ((desty + window.innerHeight - scrollfix.offset['top']) < scrollfix.getDocHeight())) {
			window.scrollBy(0,-(scrollfix.size['height'] + 5));	//A little bit of padding.
		}

		// And stop the actual click happening
		if (window.event) {
			window.event.cancelBubble = true;
			window.event.returnValue = false;
		}
		if (e && e.preventDefault && e.stopPropagation) {
			e.preventDefault();
			e.stopPropagation();
		}
	},

	// getDocHeight - return the height of the document
	getDocHeight: function() {
		var D = document;
		return Math.max(
			Math.max(D.body.scrollHeight, D.documentElement.scrollHeight),
			Math.max(D.body.offsetHeight, D.documentElement.offsetHeight),
			Math.max(D.body.clientHeight, D.documentElement.clientHeight)
		);
	}
}
