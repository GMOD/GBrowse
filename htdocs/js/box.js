/*
 This is a subclass of balloon.js -- uses a simple box rather than a 
 a balloon/bubble image.  It can have a background image and a styled
 bgcolor and border but is otherwise meant to be simple and lightweight.
*/

//////////////////////////////////////////////////////////////////////////
// This is constructor that is called to initialize the Balloon object  //
//////////////////////////////////////////////////////////////////////////
var Box = function () {
  // Track the cursor every time the mouse moves
  document.onmousemove = this.setActiveCoordinates;

  // scrolling aborts unsticky box
  document.onscroll    = Balloon.prototype.hideTooltip;

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
  var box = $('balloon');
  if (box) self.parent.removeChild(box);
  box = document.createElement('div');
  box.setAttribute('id','balloon');
  self.parent.appendChild(box);
  self.activeBalloon = box;

  var contents = document.createElement('div');
  contents.setAttribute('id','contents');
  box.appendChild(contents);
  self.contents = contents;
  self.parts = new Array(box);

  self.setStyle(contents,'zIndex',2);
  self.setStyle(contents,'color',self.fontColor);
  self.setStyle(contents,'fontFamily',self.fontFamily);
  self.setStyle(contents,'fontSize',self.fontSize);

  if (balloonIsSticky) {
    self.setStyle(contents,'margin-right',10); 
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
  self.setStyle(box,'zIndex',1000000);

  // If width and/or height are specified, harden the
  // box at those dimensions, but not if the space needed
  // is less tha the space that would be used.
  if (self.width) {
    var widthUsed = self.getLoc('contents','width') + 20;
    var newWidth = widthUsed > self.width ? self.width : widthUsed;
    self.setStyle('contents','width',newWidth);
  }
  if (self.height) {
    var heightUsed = $('contents').getStyle('height') + 20;
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

  if (self.allowFade) {
    self.setOpacity(0.01);
  }
  else {
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
  var deltaTop      = boxTop < self.pageTop ? self.pageTop - boxTop : 0;
  var deltaBottom   = boxBottom > self.pageBottom ? boxBottom - self.pageBottom : 0;

  if (vOrient == 'up' && deltaTop) {
    var newHeight = boxHeight - deltaTop;
    if (newHeight > (self.padding*2)) {
      self.setStyle('contents','height',newHeight);
      self.setStyle(box,'top',self.pageTop+self.padding);
      self.setStyle(box,'height',newHeight);
    }
  }

  if (vOrient == 'down' && deltaBottom) {
    var newHeight = boxHeight - deltaBottom - scrollBar;
    if (newHeight > (self.padding*2) + scrollBar) {
      self.setStyle('contents','height',newHeight);
      self.setStyle(box,'height',newHeight);
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
  var closeButton = $('closeButton');


  if (!closeButton) {
    closeButton = new Image;
    closeButton.setAttribute('id','closeButton');
    closeButton.setAttribute('src',self.closeButton);
    closeButton.onclick = function() {
      Balloon.prototype.hideTooltip(1);
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
  self.setStyle(closeButton,'zIndex',999999999);
}
