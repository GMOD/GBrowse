// x_img.js, X v3.15.3, Cross-Browser.com DHTML Library
// Copyright (c) 2004 Michael Foster, Licensed LGPL (gnu.org)

function xImgRollSetup(path, ovrSuffix, fileExt) 
{
  var ele, id;
  for (var i=3; i<arguments.length; ++i) {
    id = arguments[i];
    if (ele = xGetElementById(id)) {
      ele.xOutUrl = path + id + fileExt;
      ele.xOvrObj = new Image();
      ele.xOvrObj.src = path + id + ovrSuffix + fileExt;
      ele.onmouseout = imgOnMouseout;
      ele.onmouseover = imgOnMouseover;
    }
  }
  function imgOnMouseout(e)
  {
    if (this.xOutUrl) {
      this.src = this.xOutUrl;
    }
  }
  function imgOnMouseover(e)
  {
    if (this.xOvrObj && this.xOvrObj.complete) {
      this.src = this.xOvrObj.src;
    }
  }
} // end xImgRollSetup()  


/* xImgAsyncWait()

  First implementation, optimizations and fixes will probably follow.
  
  Description:

    Asynchronously waits (and monitors the status) of newly created
    or static images. Can be called before or after window.onload,
    or in the HTML following the last IMG element.
    During monitoring of image load status, your status function will
    be called at each iteration. After all images successfully load,
    your app initialization function is called. If any image fails to
    load, your error function is called.
    You can provide error and abort images for those that fail to load.
    
  Parameters:

    fnStatus  - A reference to a function which will be called at each
                iteration. It will be passed the same arguments as fnError.
                This is optional. Pass null if not needed.
    fnInit    - A reference to your application initialization function.
                It will be called after all images have successfully loaded.
    fnError   - A reference to your error function. After all images have
                loaded (or failed to load), it will be called if there was an
                error or abort. This is optional. Pass null if not needed.
                fnError will receive the following arguments:
                n - Total number of images monitored.
                c - Number of images successfully loaded.
                e - Number of images which had an error.
                a - Number of images which were aborted.
    sErrorImg - A URL to an image which will be used for any images that
                fail to load due to an error.
    sAbortImg - A URL to an image which will be used for any images that
                fail to load due to an abort.                           
    imgArray  - An array of newly created Image objects. These images will
                be monitored. If you want all static images (document.images)
                to be monitored then omit this argument.

*/

function xImgAsyncWait(fnStatus, fnInit, fnError, sErrorImg, sAbortImg, imgArray)
{
  var i, imgs = imgArray || document.images;
  
  for (i = 0; i < imgs.length; ++i) {
    imgs[i].onload = imgOnLoad;
    imgs[i].onerror = imgOnError;
    imgs[i].onabort = imgOnAbort;
  }
  
  xIAW.fnStatus = fnStatus;
  xIAW.fnInit = fnInit;
  xIAW.fnError = fnError;
  xIAW.imgArray = imgArray;

  xIAW();

  function imgOnLoad()
  {
    this.wasLoaded = true;
  }
  function imgOnError()
  {
    if (sErrorImg && !this.wasError) {
      this.src = sErrorImg;
    }
    this.wasError = true;
  }
  function imgOnAbort()
  {
    if (sAbortImg && !this.wasAborted) {
      this.src = sAbortImg;
    }
    this.wasAborted = true;
  }
}
// end xImgAsyncWait()

// Don't call xIAW() directly. It is only called from xImgAsyncWait().

function xIAW()
{
  var me = arguments.callee;
  if (!me) {
    return; // I could have used a global object instead of callee
  }
  var i, imgs = me.imgArray ? me.imgArray : document.images;
  var c = 0, e = 0, a = 0, n = imgs.length;
  for (i = 0; i < n; ++i) {
    if (imgs[i].wasError) {
      ++e;
    }
    else if (imgs[i].wasAborted) {
      ++a;
    }
    else if (imgs[i].complete || imgs[i].wasLoaded) {
      ++c;
    }
  }
  if (me.fnStatus) {
    me.fnStatus(n, c, e, a);
  }
  if (c + e + a == n) {
    if ((e || a) && me.fnError) {
      me.fnError(n, c, e, a);
    }
    else if (me.fnInit) {
      me.fnInit();
    }
  }
  else setTimeout('xIAW()', 250);
}
// end xIAW()

function xTriStateImage(idOut, urlOver, urlDown, fnUp) // Object Prototype
{
  // Downgrade Detection
  if (typeof Image != 'undefined' && document.getElementById) {
    var img = document.getElementById(idOut);
    if (img) {
      // Constructor
      var urlOut = img.src;
      var i = new Image();
      i.src = urlOver;
      i = new Image();
      i.src = urlDown;
      // Event Listener Methods (Closures)
      img.onmouseover = function()
      {
        this.src = urlOver;
      }
      img.onmouseout = function()
      {
        this.src = urlOut;
      }
      img.onmousedown = function()
      {
        this.src = urlDown;
      }
      img.onmouseup = function()
      {
        this.src = urlOver;
        if (fnUp) {
          fnUp();
        }
      }
      return this;
    }
  }
  return null;
}
