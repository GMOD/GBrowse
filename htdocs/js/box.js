/*
 This is a subclass of balloon.js -- uses a simple box rather than a 
 a balloon/bubble image.  It can have a background image and a styled
 bgcolor and border but is otherwise meant to be simple and lightweight.
*/

//////////////////////////////////////////////////////////////////////////
// This is constructor that is called to initialize the Balloon object  //
//////////////////////////////////////////////////////////////////////////
var Box = function () {

  // Get default configuration from balloon.config.js
  BoxConfig(this);

  // Track the cursor every time the mouse moves
  document.onmousemove = this.setActiveCoordinates;

  // scrolling aborts unsticky balloons
  document.onscroll    = Balloon.prototype.hideTooltip;

  // make balloons go away if the page is unloading or waiting
  // to unload.
  window.onbeforeunload = function(){
    Balloon.prototype.hideTooltip(1);
    balloonIsSuppressed = true;
  };

  // for IE, the box can't start until the page is finished loading
  // set a flag that will get toggled when loading is finished
  if (this.isIE()) {
    this.suppress = true;
  }

  return this;
}

// Inherit from Balloon class
Box.prototype = new Balloon();


// Make the box element -- this overrides the parent method
// for balloons
Box.prototype.makeBalloon = function() {
  var self = currentBalloonClass;

  var box = document.getElementById('balloon');
  if (box) self.parent.removeChild(box);

  // use ID 'balloon' for consistency with parent class
  box = document.createElement('div');
  box.setAttribute('id','balloon');
  self.parent.appendChild(box);
  self.activeBalloon = box;

  var contents = document.createElement('div');
  contents.setAttribute('id','contents');
  box.appendChild(contents);
  self.contents = contents;

  self.setStyle('contents','z-index',2);
  self.setStyle('contents','color',self.fontColor);
  self.setStyle('contents','font-family',self.fontFamily);
  self.setStyle('contents','font-size',self.fontSize);

  if (balloonIsSticky) {
    self.setStyle('contents','margin-right',10); 
  }
  else if (self.displayTime)  {
      self.timeoutAutoClose = window.setTimeout(this.hideTooltip,self.displayTime);
  }
  return box;
}

// Set the box style -- overrides the parent method for balloons
Box.prototype.setBalloonStyle = function(vOrient,hOrient,pageWidth,pageLeft) {
  var self = currentBalloonClass;
  var box = self.activeBalloon;

  var fullPadding   = self.padding;
  var insidePadding = self.padding;

  self.setStyle(box,'background',self.bgColor);
  self.setStyle(box,'border',self.borderStyle);
  self.setStyle(box,'position','absolute');
  self.setStyle(box,'padding',fullPadding);
  self.setStyle(box,'top',-9999);
  self.setStyle(box,'z-index',1000000);
  if (self.width) {	
    self.setStyle(box,'width',self.width);
  }  

  // flip left or right, as required
  if (hOrient == 'left') {
    var activeRight = pageWidth - self.activeLeft;
    self.setStyle(box,'right',activeRight);// - self.xOffset);
  }
  else {
    self.setStyle(box,'left',self.activeRight - self.xOffset);
  }

  // have to harden the width
  if (!self.width) {
    var width = self.getLoc('contents','width');
    if (self.isIE()) width += 50;
    if (width > self.maxWidth) width = self.maxWidth + 50;
    if (width < self.minWidth) width = self.minWidth;
    self.setStyle(box,'width',width);
  }
  else {
    self.setStyle(box,'width',self.width);
  }

  // Make sure the box is not offscreen
  var boxPad   = self.padding;
  var boxLeft  = self.getLoc(box,'x1');
  var boxRight = self.getLoc(box,'x2');
  if (hOrient == 'left')  boxLeft  += boxPad;
  if (hOrient == 'right') boxRight += boxPad;
  var pageRight    = pageLeft + pageWidth;

  if (hOrient == 'right' && boxRight > (pageRight-30)) {
    self.setStyle(box,'width',(pageRight - boxLeft) - 50);
  }
  else if (hOrient == 'left' && boxLeft < (pageLeft+30)) {
    self.setStyle(box,'width',(boxRight - pageLeft) - 50);
  }
  
  if (vOrient == 'up') {
    var boxHeight = self.getLoc(box,'height') + self.vOffset;
    var activeTop = self.activeTop - boxHeight;
    self.setStyle(box,'top',activeTop);
    self.setStyle(box,'display','inline');
  }
  else {
    var activeTop = self.activeBottom - self.vOffset;
    self.setStyle(box,'top',activeTop);
  }

  self.setOpacity(1);
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
    };
    self.setStyle(closeButton,'position','absolute');
    document.body.appendChild(closeButton);
  }

  self.setStyle(closeButton,'top',balloonTop);
  self.setStyle(closeButton,'left',balloonRight);
  self.setStyle(closeButton,'display','inline');
  self.setStyle(closeButton,'cursor','pointer');
  self.setStyle(closeButton,'z-index',999999999);
}
