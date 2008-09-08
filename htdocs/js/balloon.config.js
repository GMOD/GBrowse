/* 
This file contains the default configuration options.  
Default options can be edited in this file or changed after the Balloon object is 
initiliazed as follows:

  var balloon = new Balloon;
  balloon.fontColor   = 'black';
  balloon.fontFamily  = 'Arial, sans-serif';
  balloon.fontSize    = '12pt';

*/

// Adds all the instance variables to the balloon object.
// Edit the values as required for your implementation.
BalloonConfig = function(balloon) {

  // ID of element to which balloon should be added
  // default = none (document.body is used)
  // Balloon option may be required for mediawiki or other
  // implementations with complex stylesheets
  balloon.parentID = null;

  // properties of fonts contained in basic balloons (default black)
  balloon.fontColor   = 'black';
  balloon.fontFamily  = 'Arial, sans-serif';
  balloon.fontSize    = '12pt';

  // minimum allowed balloon width (px)
  balloon.minWidth = 150;

  // maximum allowed balloon width (px)
  balloon.maxWidth = 600;

  // Delay before balloon is displayed (msec)
  balloon.delayTime = 500;

  // If fade-in/out is allowed
  balloon.allowFade = false;

  // time interval for fade-in (msec)
  balloon.fadeIn    = 300;

  // time interval for fade-out (msec)
  balloon.fadeOut   = 300;  

  // Vertical Distance from cursor location (px)
  balloon.vOffset  = 10;

  // text-padding within the balloon (px)
  balloon.padding  = 10;

  // How long to display mousover balloons (msec)
  // false = 'always on'
  balloon.displayTime = 10000;

  // width of shadow (space aroung whole balloon; px)
  // Balloon can be zero if there is no shadow and the
  // edges of the balloon are also the edges of the image
  balloon.shadow   = 20;

  // images of balloon body.  If the browser is IE < 7, png alpha
  // channels will not work.  An optional alternative image can be 
  // provided.  It should have the same dimensions as the default png image
  balloon.images        = '/images/balloons';
  balloon.balloonImage  = 'balloon.png';    // with alpha channels
  balloon.ieImage       = 'balloon_ie.png'; // indexed color, transparent background

  // whether the balloon should have a stem
  balloon.stem          = true;

  // The height (px) of the stem and the extent to which the 
  // stem image should overlaps the balloon image.
  balloon.stemHeight  = 32;  
  balloon.stemOverlap = 3;
  
  // A stem for each of the four orientations
  balloon.upLeftStem    = 'up_left.png';
  balloon.downLeftStem  = 'down_left.png';
  balloon.upRightStem   = 'up_right.png';
  balloon.downRightStem = 'down_right.png';

  // A close button for sticky balloons
  // specify the width of your button image
  // if you do not use the default image provided
  balloon.closeButton   = 'close.png';
  balloon.closeButtonWidth = 16;


  // support for AJAX, iframes and JavaScript in balloons
  // If you have concerns about XSS vulnerabilities, set some or all of these
  // values to false;
  balloon.helpUrl            = false;
  balloon.allowAJAX          = true;
  balloon.allowIframes       = true;
  balloon.allowEventHandlers = false;
  balloon.allowScripts       = false;
}
