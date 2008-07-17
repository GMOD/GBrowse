/* $Id: bookmark.js,v 1.1.2.2 2008-07-17 03:29:23 lstein Exp $ 
* Modified from the dynamic drive dhtml code library, whose copyright appears
* below.
*/

/***********************************************
* Bookmark site script- © Dynamic Drive DHTML code library (www.dynamicdrive.com)
* This notice MUST stay intact for legal use
* Visit Dynamic Drive at http://www.dynamicdrive.com/ for full source code
***********************************************/


/* Modified to support Opera */
function bookmarksite(title,url){
    if (window.sidebar) {// firefox
	window.location.href=url;
	alert("You may now add this page's URL to your bookmarks.");
    }
    else if(window.opera && window.print){ // opera
	var elem = document.createElement('a');
	elem.setAttribute('href',url);
	elem.setAttribute('title',title);
	elem.setAttribute('rel','sidebar');
	elem.click();
    } 
    else if(document.all)// ie
	window.external.AddFavorite(url, title);
}
