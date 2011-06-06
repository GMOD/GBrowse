/*
 This is a subclass of balloon.js -- uses a simple box rather than a 
 a balloon/bubble image.  It can have a background image and a styled
 bgcolor and border but is otherwise meant to be simple and lightweight.
*/

var Modal=false; // true if a modal dialog is on screen

//////////////////////////////////////////////////////////////////////////
// This is constructor that is called to initialize the Balloon object  //
//////////////////////////////////////////////////////////////////////////
var Box = function () {
  // Track the cursor every time the mouse moves
  document.onmousemove = this.setActiveCoordinates;

  // scrolling aborts unsticky balloons
  document.onscroll    = Balloon.prototype.hideTooltip;

  // for IE, the balloons can;t start until the page is finished loading
  // set a flag that will get toggled when loading is finished
  if (this.isIE()) {
      this.suppress = true;
  } else {
      // make balloons go away if the page is unloading or waiting
      // to unload.
      window.onbeforeunload = function(){
            Balloon.prototype.hideTooltip(1);
            balloonIsSuppressed = true;
      };
  }

  return this;
}

// Inherit from Balloon class
Box.prototype = new Balloon();


// Make the box element -- this overrides the parent method
Box.prototype.makeBalloon = function() {
  var self = currentBalloonClass;
  
  // use ID 'balloon' for consistency with parent class
  var box = document.getElementById('balloon');
  if (box) self.parent.removeChild(box);
  box = document.createElement('div');
  box.setAttribute('id','balloon');

  self.parent.appendChild(box);
  self.activeBalloon    = box;

  var contents = document.createElement('div');
  contents.setAttribute('id','contents');
  box.appendChild(contents);
  self.contents = contents;
  self.parts = new Array(box);

  self.setStyle(contents,'z-index',2);
  self.setStyle(contents,'color',self.fontColor);
  self.setStyle(contents,'font-family',self.fontFamily);
  self.setStyle(contents,'font-size',self.fontSize);

  if (balloonIsSticky) {
    self.setStyle(contents,'margin-top',self.closeButtonWidth);
  }
  else if (self.displayTime)  {
    self.timeoutAutoClose = window.setTimeout(this.hideTooltip,self.displayTime);
  }

  return box;
}

// Set the box style -- overrides the parent method
Box.prototype.setBalloonStyle = function(vOrient,hOrient) {
  var self = currentBalloonClass;
  var box  = self.activeBalloon;

  self.shadow     = 0;
  self.stem       = false;
  self.stemHeight = 0;

  self.setStyle(box,'background',self.bgColor);
  self.setStyle(box,'border',self.borderStyle);
  self.setStyle(box,'position','absolute');
  self.setStyle(box,'padding',self.padding);
  self.setStyle(box,'top',-9999);
  self.setStyle(box,'z-index',1000000);

  // If width and/or height are specified, harden the
  // box at those dimensions, but not if the space needed
  // is less tha the space that would be used.
  if (self.width) {
    var widthUsed = self.getLoc('contents','width');
    var newWidth = widthUsed > self.width ? self.width : widthUsed;
    self.setStyle('contents','width',newWidth);
  }
  if (self.height) {
    var heightUsed = self.getLoc('contents','height');
    var newHeight = heightUsed > self.height ? self.height : heightUsed;
    self.setStyle('contents','height',newHeight+(2*self.padding));
  }

  // flip left or right, as required
  if (hOrient == 'left') {
    var pageWidth = self.pageRight - self.pageLeft;
    var activeRight = pageWidth - self.activeLeft;
    self.setStyle(box,'right',activeRight);
  }
  else {
    self.setStyle(box,'left',self.activeRight - self.xOffset);
  }

  if (!self.width) {
    var width = self.getLoc('contents','width');
    if (self.isIE()) width += self.padding;
    if (width > self.maxWidth) width = self.maxWidth + self.padding;
    if (width < self.minWidth) width = self.minWidth;
    self.setStyle(box,'width',width);
  }

  var overflow = balloonIsSticky ? 'auto' : 'hidden';
  self.setStyle('contents','overflow',overflow);

  // Make sure the box is not offscreen horizontally.
  // We handle vertical sanity checking later, after the final
  // layout is set.
  var boxLeft   = self.getLoc(box,'x1');
  var boxRight  = self.getLoc(box,'x2');
  var scrollBar     = 20;

  if (hOrient == 'right' && boxRight > (self.pageRight - self.padding)) {
    self.setStyle('contents','width',(self.pageRight - boxLeft) - self.padding - scrollBar);
  }
  else if (hOrient == 'left' && boxLeft < (self.pageLeft + self.padding)) {
    self.setStyle('contents','width',(boxRight - self.pageLeft) - self.padding);
  }

  // Get the width/height for the right and bottom outlines
  var boxWidth  = self.getLoc(box,'width');
  var boxHeight = self.getLoc(box,'height');

  if (self.opacity) {
    self.setOpacity(self.opacity);
  }

  if (!(self.activeTop && self.activeBottom)) {
    self.setActiveCoordinates();
  }

  if (vOrient == 'up') {
    var activeTop = self.activeTop - boxHeight;
    self.setStyle(box,'top',activeTop);
  }
  else if (vOrient == 'down')  {
    var activeTop = self.activeBottom;
    self.setStyle(box,'top',activeTop);
  }
  self.setStyle(box,'display','inline');

  // Make sure the box is vertically contained in the window
  var boxTop    = self.getLoc(box,'y1');
  var boxBottom = self.getLoc(box,'y2');
  
  if (boxBottom > self.pageBottom) {
      var delta    = boxBottom - self.pageBottom;
      var newTop   = boxTop - delta;
      self.setStyle(box,'top',newTop);
      boxBottom = self.pageBottom;
      boxTop    = newTop;
  } 

  if (boxTop < self.pageTop) {
      self.setStyle(box,'top',self.pageTop+self.padding);
      boxTop    = self.pageTop+self.padding;
      boxBottom = boxTop + boxHeight;
      if (boxBottom > self.pageBottom) {
	  var newHeight = (self.pageBottom - boxTop) - 2*self.padding;
	  self.setStyle(box,'height',newHeight);
	  self.setStyle('contents','height',newHeight - 2*self.padding);
      }
  }

  self.hOrient = hOrient;
  self.vOrient = vOrient;
}


Box.prototype.addCloseButton = function () {
  var self = currentBalloonClass;
  var margin   = Math.round(self.padding/2);
  var closeWidth = self.closeButtonWidth || 16;
  var balloonTop   = self.getLoc('balloon','y1') + margin;
  var balloonRight = self.getLoc('balloon','x2') - margin - self.closeButtonWidth;
  var closeButton = document.getElementById('closeButton');

  if (!closeButton) {
    closeButton = new Image;
    closeButton.setAttribute('id','closeButton');
    closeButton.setAttribute('src',self.closeButton);
    closeButton.onclick = function() {
      Balloon.prototype.hideTooltip(1);
      self.greyout(false);
    };
    self.setStyle(closeButton,'position','absolute');
    document.body.appendChild(closeButton);
  }

  if (self.isIE()) {
    balloonRight -= self.padding;
  }

  self.setStyle(closeButton,'top',balloonTop);
  self.setStyle(closeButton,'left',balloonRight);
  self.setStyle(closeButton,'display','inline');
  self.setStyle(closeButton,'cursor','pointer');
  self.setStyle(closeButton,'z-index',999999999);
}

Box.prototype.greyout = function (turnOn) {
    //Adapted from http://www.hunlock.com/blogs/Snippets:_Howto_Grey-Out_The_Screen
    var greyout  = $('greyout');
    if(!greyout) {
        var contents = $$('body')[0];
        var div      = document.createElement('div');
	div.id                    = 'greyout';
	div.style.backgroundColor = '#000000';
	div.style.display         = 'none';
	div.style.filter          = 'alpha(opacity=70)';
	div.style.height          = '100%';
	div.style.left            = '0px';
	div.style.MozOpacity      = '0.7';
	div.style.opacity         = '0.7';
	div.style.overflow        = 'hidden';
	div.style.position        = 'absolute';
	div.style.top             = '0px';
	div.style.width           = '100%';
	div.style.zIndex          = 0;
	contents.appendChild(div);
	greyout=$('greyout');
    }
    if (turnOn && !Modal) {
        document.body.style.overflow = 'hidden';
        greyout.style.display         = 'block';
    } else if (Modal) {
        document.body.style.overflow = 'auto';
        greyout.style.display         = 'none';
    }
    Modal=turnOn;
}

Box.prototype.modalDialog = function(evt,caption,width,height) {
    this.showTooltip(evt,caption,true,width,height);
    this.greyout(true);
}

Box.prototype.hideTooltip = function(override) {
    this.greyout(false);
    Balloon.prototype.hideTooltip(override);
}
