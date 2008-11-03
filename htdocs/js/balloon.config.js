/* 

This file contains the default configuration options for GBrowse balloon tooltips.
Default options can be edited in this file or changed after the Balloon object is 
initiliazed as follows:

  var balloon = new Balloon;
  balloon.fontColor   = 'black';
  balloon.fontFamily  = 'Arial, sans-serif';
  balloon.fontSize    = '12pt';
  etc...

*/


// This function adds the default configuration and also custom 
// configuration sets, specifioed in 'case' stanzas
BalloonConfig = function(balloon, set) {
  set = set || '';

  ////////////////////////////////////////////////////////////////
  // The default "base" config applied to all balloon objects.  //
  // See http://gmod.org/wiki/Popup_Balloons#Customization for  //
  // details about config options                               //
  //                                                            //
  // values can be overriden in custom config cases (see below) //
  ////////////////////////////////////////////////////////////////
  if (!balloon.configured) {                                    //
    balloon.fontColor          = 'black';                       //
    balloon.fontFamily         = 'Arial, sans-serif';           //
    balloon.fontSize           = '12pt';                        //
    balloon.minWidth           = 100;                           //
    balloon.maxWidth           = 400;                           //
    balloon.delayTime          = 750;                           //
    balloon.vOffset            = 10;                            //
    balloon.hOffset            = 10;                            //
    balloon.stem               = true;                          //
    balloon.balloonImage       = 'balloon.png';                 //
    balloon.upLeftStem         = 'up_left.png';                 //
    balloon.downLeftStem       = 'down_left.png';               //
    balloon.upRightStem        = 'up_right.png';                //
    balloon.downRightStem      = 'down_right.png';              //
    balloon.closeButton        = 'close.png';                   //
    balloon.closeButtonWidth   = 16;                            //
    balloon.allowAJAX          = true;                          //
    balloon.allowIframes       = true;                          //
    balloon.configured         = true;                          //
    balloon.trackCursor        = true;                          //
  }                                                             //
  ////////////////////////////////////////////////////////////////


  ////////////////////////////////////////////////////////////////
  // Custom configuration options -- Add a case below for your  //
  // config set (GBrowse defaults: GBox, GPlain and GBubble)    //
  ////////////////////////////////////////////////////////////////
  switch(set) {

    // A formatted box (no background image)
    case('GBox') : 
      balloon.bgColor     = 'lightgoldenrodyellow';
      balloon.borderStyle = '2px solid gray'; 
      balloon.padding     = 5;
      balloon.shadow      = 0;
      balloon.stem        = false;
      balloon.opacity     = 90;
      break;

    // A simple balloon (current favorite)    
    case('GPlain') : 
      balloon.padding     = 5;  
      balloon.shadow      = 0;  
      balloon.stemHeight  = 15;
      balloon.stemOverlap = 1;
      balloon.opacity     = 85;
      break;

    // The original cartoon bubble
    case('GBubble') : 
      balloon.ieImage     = 'balloon_ie.png'; 
      balloon.shadow      = 20;               
      balloon.padding     = 10;               
      balloon.stemHeight  = 32;               
      balloon.stemOverlap = 3;                
      balloon.vOffset     = 1; 
      balloon.hOffset     = 1; 
      balloon.opacity     = 85;
      balloon.trackCursor = false;
      break;

    // The cartoon bubble with a fade-in effect
    case('GFade') :
      balloon.ieImage     = 'balloon_ie.png';
      balloon.shadow      = 20;
      balloon.padding     = 10;
      balloon.stemHeight  = 32;
      balloon.stemOverlap = 3;
      balloon.vOffset     = 1;
      balloon.hOffset     = 1;
      balloon.opacity     = 85;
      balloon.allowFade   = true;
      balloon.trackCursor = false;
      break;
  }
}

