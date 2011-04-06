/*

 rubber.js -- a base class for drag/rubber-band selection in gbrowse

 Sheldon McKay <mckays@cshl.edu>
 $Id$

*/

var currentSelectArea;
var selectAreaIsActive;
var lefttemp; 

// Constructor
var SelectArea = function () {
    this.background = 'yellow';
    this.unit      = 'bp';
    this.divider   = 1;
  return this;
}

// replace image or image button that will conflict with drag selection
SelectArea.prototype.replaceImage = function(image) {
  var src    = image.getAttribute('src');
  var name   = image.getAttribute('name');
  var isIE   = document.all && !window.opera; 


  var id = image.getAttribute('id');
  var width  = this.elementLocation(image,'width');
  var height = this.elementLocation(image,'height');
  var top    = this.elementLocation(image,'y1');
  var left   = this.elementLocation(image,'x1');

  var p = image.parentNode;
  p.removeChild(image);

  image = this.createAndAppend('span',p,id);
  image.setAttribute('name',name);

  // escape backslashes that may appear in the src attribute
  src = escape(src.replace(/\\/g,"\\\\"));

  image = Element.extend(image);
  image.setStyle({ background: 'url('+src+') top left no-repeat',
                   width: width+'px',
                   height: height+'px',
                   display: 'block',
                   cursor: 'text' 
  });


  if (   !document.searchform 
      || !document.searchform.drag_and_drop 
      || !document.searchform.drag_and_drop.checked) {
    var name = this.imageId+'_map';
    var map;
    
    //IE but this time it is the DOM compliant one
    if (isIE) {
      var spans  = document.getElementsByTagName('span');
      var map = new Array;
      for (var n=0;n<spans.length;n++) {
        if (spans[n].name == name) {
          map.push(spans[n]);
        }
      }
      // Why? I really don't know!
      top  = top  - 6;
      left = left - 6;
    }
    else {
      map = document.getElementsByName(name);
    }

    if (map && map.length) {
      for (var n=0;n<map.length;n++) {
        var newTop   = this.elementLocation(map[n],'y1') + top;
        var newLeft  = this.elementLocation(map[n],'x1') + left;
        map[n].setStyle({ top: newTop+'px',
                          left: newLeft+'px'
        });
      }
    }
  }

  return image;
}

SelectArea.prototype.recenter = function(event) {
  var self = currentSelectArea;
  self.loadSegmentInfo();
  var deltaPixelStart      = self.selectPixelStart - self.pixelStart;
  var deltaSequenceStart   = deltaPixelStart * self.pixelToDNA;

  var coord  = self.flip ? Math.round(self.segmentEnd - deltaSequenceStart)
                         : Math.round(self.segmentStart + deltaSequenceStart);

  var end  = self.segmentEnd;
  var span = Math.abs(TrackPan.viewable_segment_length);
  var half = Math.round(span/2);

  // don't fall off the ends
  if (coord < 0)   coord = half + 1;
  if (coord > end) coord = end - half - 1;
  var start  = coord - half;
  var end    = coord + half;

  if (start > end){ 
    var tmp = end;
    end = start;
    start = tmp;
  }
  
  if (start >= this.detailStart && end <= this.detailEnd) {
    // The segment is already loaded - just scroll to it
    var scroll_to = TrackPan.position_from_start(start);
    TrackPan.update_pan_position(scroll_to); 
  } else {
    self.currentSegment = self.ref + ':' + start + '..' + end;
    if (document.searchform) {
      document.searchform.name.value = self.currentSegment;
    }
    self.submit();
  }
}

// Cross-browser element coordinates
SelectArea.prototype.elementLocation = function(el,request) {
  var offset = $(el).cumulativeOffset();
  var dimensions = $(el).getDimensions();
  switch(request) {
    case ('y1') : return offset.top;
    case ('y2') : return offset.top + dimensions.height;
    case ('x1') : return offset.left;
    case ('x2') : return offset.left + dimensions.width;
    case ('width')  : return dimensions.width;
    case ('height') : return dimensions.height;
 }
}


// Cross-browser event coordinates
SelectArea.prototype.eventLocation = function(event,request) {
  var e = event || window.event;
  if (request == 'x') {
    return Event.pointerX(e) || Event.clientX(e) + document.body.scrollLeft + document.documentElement.scrollLeft;
   
    
  }
  else if (request == 'y') {
    return Event.pointerY(e) || Event.clientY(e) + document.body.scrollTop  + document.documentElement.scrollTop;
 
  }
  else {  
    return false;
  }
}

// Fired when there is a mousedown between the top and bottom
// of the selectable image -- horizontal position does not matter
SelectArea.prototype.startRubber = function(self,event) {
  // only one select area is active at a time, so let the subclass take possession

  self.loadSegmentInfo();

  currentSelectArea = self;

  // suppress all popup balloon while drag-select is active
  Balloon.prototype.hideTooltip(1);  
  balloonIsSuppressed = true;

  // disable help balloon after first selection is made.
  var nullfunc = function(){return false};
  self.scalebar.onmouseover = nullfunc;
 
  // set the selectbox bgcolor
  self.setOpacity(self.selectBox,self.opacity||0.5);  

  // deal with drag/select artifacts
  self.disableSelection(self.selectLayer);

  self.selectPixelStart = self.eventLocation(event,'x') - self.elementLocation(self.selectLayer,'x1');

  self.selectBox.setStyle({ visibility: 'hidden',
                            left: self.selectPixelStart+'px',
                            width: '2px',
                            textAlign: 'center',
                            visibility: 'hidden' 
  });

  var spanReport = Element.extend(self.spanReport || self.createAndAppend('p',self.selectBox,'spanReport'));
  spanReport.setStyle({ color: self.fontColor||'black',
                        marginTop: self.marginTop||'0px',
                        background: 'transparent',
                        font: 'normal bold 14px sans-serif'
  });

  spanReport.innerHTML = ' ';
  self.spanReport = spanReport;
  selectAreaIsActive = true;
}

SelectArea.prototype.cancelRubber = function() {
  var self = currentSelectArea || new SelectArea;
  balloonIsSuppressed = false;

  if (!self.selectBox) return false;
  
  self.selectBox.setStyle({visibility:'hidden'});
  self.selectMenu.setStyle({visibility:'hidden'});
  selectAreaIsActive = false;

  if (self.originalLandmark) {
    document.searchform.name.value = self.originalLandmark;
  }
  self.moved = false;
}

SelectArea.prototype.round = function(nearest,num) {
  if (num > nearest) {
    num = Math.round(num/nearest)*nearest;
  }
  return num;
} 

SelectArea.prototype.moveRubber = function(event) {
  if (!selectAreaIsActive) return false;

  var self = currentSelectArea;
  var selectPixelStart = self.selectPixelStart;
  var selectPixelEnd   = self.eventLocation(event,'x') - self.elementLocation(self.selectLayer,'x1');
   lefttemp   = selectPixelEnd;
  var selectPixelWidth = Math.abs(selectPixelStart - selectPixelEnd);

  var rev, left;
  if (selectPixelStart > selectPixelEnd) {
    rev  = true;
    left = selectPixelEnd;
    self.selectPixelStart = left;
  }
  else {
    left = selectPixelStart;
  }

  // Coordinates of selected sequence
  var deltaPixelStart      = left - self.pixelStart;
  var deltaSequenceStart   = deltaPixelStart * self.pixelToDNA;
  self.selectSequenceStart = self.flip ? Math.round(self.segmentEnd - deltaSequenceStart) 
                                       : Math.round(self.segmentStart + deltaSequenceStart);
  var selectSequenceWidth  = Math.round(selectPixelWidth * self.pixelToDNA);
  self.selectSequenceEnd   = self.flip ? self.selectSequenceStart - selectSequenceWidth 
                                       : self.selectSequenceStart + selectSequenceWidth;

  var segmentLength = Math.abs(self.segmentEnd - self.segmentStart);
  
  // Round the sequence coordinates to the nearest appropriate 10x
  if (segmentLength > 1000000) {
    self.selectSequenceStart = self.round(10000,self.selectSequenceStart);
    self.selectSequenceEnd = self.round(10000,self.selectSequenceEnd);
  }
  else if (segmentLength > 50000) {
    self.selectSequenceStart = self.round(1000,self.selectSequenceStart);
    self.selectSequenceEnd = self.round(1000,self.selectSequenceEnd);
  }
  else if (segmentLength > 5000) {
    self.selectSequenceStart = self.round(100,self.selectSequenceStart);
    self.selectSequenceEnd = self.round(100,self.selectSequenceEnd);
  }
  else if (segmentLength > 500) {
    self.selectSequenceStart = self.round(10,self.selectSequenceStart);
    self.selectSequenceEnd = self.round(10,self.selectSequenceEnd);
  }
  
  selectSequenceWidth = Math.abs(self.selectSequenceEnd - self.selectSequenceStart);

  // Don't allow the start to be > the end
  if (self.selectSequenceStart > self.selectSequenceEnd){ 
    var tmp = self.selectSequenceEnd;
    self.selectSequenceEnd = self.selectSequenceStart;
    self.selectSequenceStart = tmp;
  }

  // reset the value of the 'name' input box
  self.currentSegment = self.ref +':'+self.selectSequenceStart+'..'+(self.selectSequenceEnd-1);
  if (document.searchform) {
    document.searchform.name.value = self.currentSegment;
  } 

  // size and appearance of the "rubber band" select box
  self.selectBox.setStyle({left: left+'px',
                           width: selectPixelWidth+'px',
                           visibility: 'visible'
  });

  // warning if max segment size exceeded
  var tooBig;
  if (self.max_segment && selectSequenceWidth > self.max_segment) {
    self.setOpacity(self.selectBox,self.opacity||0.5,'red');
    self.overrideAutoSubmit = true;
    tooBig = true;
  }
  else {
    self.setOpacity(self.selectBox,self.opacity||0.5);
    self.overrideAutoSubmit = false;
  }

  var unit     = self.unit;
  var divider  = self.divider;
  selectSequenceWidth /= divider;
  if (selectSequenceWidth > 1000 && selectSequenceWidth < 1000000) {
    selectSequenceWidth = selectSequenceWidth/1000;
    unit = 'k'+unit;
  }
  else if (selectSequenceWidth > 1000000) {
    selectSequenceWidth = selectSequenceWidth/1000000;
    unit = 'M'+unit;
  }

  if (Math.floor(selectSequenceWidth) != selectSequenceWidth) {
    selectSequenceWidth = selectSequenceWidth.toFixed(2);
  }

  if (selectPixelWidth > 20) {
    self.spanReport.innerHTML = selectSequenceWidth+' '+unit;
  }
  else {
    self.spanReport.innerHTML = ' ' ;
  }

  self.selectPixelStart = selectPixelStart;

  // Only count as moved if the pixel change is greater than 1
  // This is to make it easier to simply recenter
  if (selectPixelWidth > 1){
    self.moved = true;
  }
}

// taken from http://ajaxcookbook.org/disable-text-selection/
// prevents ugly drag select side-effects
SelectArea.prototype.disableSelection = function(el) {
    el.onselectstart = function() {
        return false;
    };
    el.unselectable = "on";
    el.style.MozUserSelect = "none";
    el.style.cursor = "default";
}


// Builds the popup menu that appears when selection is complete
SelectArea.prototype.addSelectMenu = function(view) {

  var menu =  $(view+'SelectMenu'); 
  if (menu) {
    this.autoSubmit = false;
  }
  else {
    menu = this.createAndAppend('div',document.body,view+'SelectMenu');
  }

  // required style 
  menu = Element.extend(menu);
  menu.setStyle({ position: 'absolute',
                  display: 'block',
                  zIndex: '101',
                  visibility: 'hidden'
  });

  // optional style -- check if a custom menu has styles set already
  var existingStyle = new String(menu.getAttribute('style'));
  if (existingStyle) {
    if (!existingStyle.match(/width/i))      menu.setStyle({ width: this.menuWidth||'200px'});
    if (!existingStyle.match(/font/i))       menu.setStyle({ font: '12px sans-serif'});
    if (!existingStyle.match(/background/i)) menu.setStyle({ background: 'lightyellow'});
    if (!existingStyle.match(/border/i))     menu.setStyle({ border: '1px solid #003366'});
  }

  this.selectMenu = menu;
  this.formatMenu();
}

// Initial creation of the select box
SelectArea.prototype.addSelectBox = function(view) {
  
  var supportsTouch = ('createTouch' in document);

  if (this.selectBox) return false;
 
  var box = this.createAndAppend('div',this.selectLayer,view+'selectBox');
  box     = Element.extend(box);
  box.setStyle({ position: 'absolute',
                 visibility: 'hidden',
                 top: '0px',
                 height: '100%',
                 left: '0px',
                 zIndex: 100,
                 border: this.border||'none' });
// 
 /* // click on scalebar initializes selection
  this.scalebar.onmousedown      = this.startSelection;

  // drag and mouseup on details panel fires menu
  this.selectLayer.onmousemove   = this.moveRubber;
  this.selectLayer.onmouseup     = this.stopRubber;  

  // allows drag-back*/
 

/* this.scalebar[supportsTouch ? 'ontouchmove' : 'onmousedown'] = this.startSelection;
 
 this.selectLayer[supportsTouch ? 'ontouchmove' : 'onmousemove'] = this.moveRubber;
 
 this.selectLayer[supportsTouch ? 'ontouchend' : 'onmouseup'] = this.stopRubber;
 */
 if ('createTouch' in document) {
  this.scalebar.ontouchstart = this.startSelection;
  event.preventDefault();
  
  // drag and mouseup on details panel fires menu
  this.selectLayer.ontouchmove   = this.moveRubber;
  this.selectLayer.ontouchend     = this.stopRubber;  
  } else {
    this.scalebar.onmousedown = this.startSelection;

  // drag and mouseup on details panel fires menu
  this.selectLayer.onmousemove   = this.moveRubber;
  this.selectLayer.onmouseup   = this.stopRubber;
    
  }


  // 'esc' key aborts
  var abort = function(event){
    var evt = event || window.event;
    if (evt.keyCode == 27) SelectArea.prototype.cancelRubber();
    return true;
  }
  document.onkeydown        = abort;

  this.selectBox = box;
}


/////////////////////////////////////////////////////////////////////
// Create/append  elements
/////////////////////////////////////////////////////////////////////

SelectArea.prototype.createAndAppend = function(elTag,parent,id) {
  var node = this.justCreate(elTag);
  this.justAppend(node,parent);
  if (id) node.setAttribute('id',id);
  return node;
}

SelectArea.prototype.justCreate = function(elTag) {
  var tag = elTag || 'div';
  var node = document.createElement(tag);
  return node;
}

SelectArea.prototype.justAppend = function(child,parent) {
  var parentNode = parent || document.body;
  parentNode.appendChild(child);
}
  

SelectArea.prototype.stopRubber = function(event) {
  balloonIsSuppressed = false;
  if (!selectAreaIsActive) return false;
  var self = currentSelectArea;
  if (!self.moved) {
    self.cancelRubber();
    self.recenter();
    return false;
  }

  selectAreaIsActive = false;
  self.moved = false;

  // autoSubmit option will bypass the menu
  if (self.autoSubmit && !self.overrideAutoSubmit) {
    SelectArea.prototype.cancelRubber();
    //document.searchform.submit();
    self.submit();
  }
  else {
    self.showMenu(event);
  }
}

SelectArea.prototype.showMenu = function(event) {
  var self = currentSelectArea;
  var menu = self.selectMenu;
  menu.innerHTML = self.menuHTML.replace(/SELECTION/g,self.currentSegment);

  var pageWidth  =
  document.viewport.getWidth();
  var menuWidth  = self.elementLocation(menu,'width');
  var menuHeight = self.elementLocation(menu,'height');
  var menuYHalf  = Math.round(menuHeight/2); 
  
  if ('createTouch' in document){
  var left = lefttemp+50;
  var top = 440;
  } else {
  var left = self.eventLocation(event,'x') + 20;
  if ((left+menuWidth) > pageWidth) left -= menuWidth + 10;
  var top  = self.eventLocation(event,'y')+30;
  }
  menu = Element.extend(menu);
  menu.setStyle({ top:  top+'px' }); 
  menu.setStyle({ left: left+'px' });

  // Abort if there is no selection
  if (self.selectBox.getStyle('visibility') == 'hidden') {
    self.cancelRubber;
    return false;
  }

  menu.setStyle({ visibility: 'visible' });

}

SelectArea.prototype.hideMenu = function() {
  var self = currentSelectArea;

  self.selectBox.setStyle({ width: 1,
                            visibility: 'hidden'
  });
  self.selectMenu.setStyle({visibility: 'hidden'});
}

SelectArea.prototype.clearAndSubmit = function(plugin,action) {
  this.hideMenu();
  if (plugin) {
    action = action || 'Go';
    var url = window.location;
    url += '?plugin='+plugin+';plugin_do='+action; 
    document.location = url;
  }
  else {
    this.submit();
  }
}

SelectArea.prototype.clearAndRecenter = function() {
  this.hideMenu();
  var self = currentSelectArea;
  self.loadSegmentInfo();
  var start   = self.detailStart+'';
  start   = start.replace(/\D+/,'') * 1;
  var end   = self.detailEnd+'';
  end   = end.replace(/\D+/,'') * 1;
  var half    = Math.round(Math.abs((end - start)/2));
  var middle  = Math.round((self.selectSequenceStart + self.selectSequenceEnd)/2);
  var newName = self.ref+':'+(middle-half)+'..'+(middle+half);
  self.currentSegment = newName;
  self.submit();
}

// Make best effort to set the opacity of the selectbox
// background color
SelectArea.prototype.setOpacity = function(el,opc,bgColor) {
  var self = currentSelectArea;
  if (!bgColor) {
    bgColor = self.background;
  }
  
  if (!(el && opc)) return false;

  opc = parseFloat(opc);
  el.setStyle({ background: bgColor||'#BABABA',
                opacity: opc 
             });
}


SelectArea.prototype.submit = function() {
  var self = currentSelectArea;
  if (Controller.gbrowse_syn) {
    Controller.update_coordinates(self.currentSegment);
  }
  else if (self.currentSegment) {
    Controller.update_coordinates("set segment " + self.currentSegment);
  }  
}
