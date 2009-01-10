// helper utilities for the karyotype module.

function k_dohilite (el,hilite_it,autoscroll) {

    var classname   = hilite_it ? 'hilite' : 'nohilite';

    Element.extend(el);
    var id    = el.identify();
    var base  = id.gsub(/^\w+_/,'');

    if (autoscroll) {
	var f = $('feature_'+base);
	// for some reason this kills IE and causes the rows to
	// lose their fgcolor
    	// var top = f.positionedOffset().top;
	var top = 0;
	var e   = f;
	while (e) {
	    top += e.offsetTop;
	    e    = e.offsetParent;
	    if (e==null) break;
	    if (e.tagName.toUpperCase() == 'BODY') break;
	    if (Element.getStyle(e,'position') != 'static') break;
	}
	$('scrolling_table').scrollTop = top;
     }

     var el;

     if ((el = $('box_'+base)) != null)
         el.className     = classname;
     if ((el = $('feature_'+base)) != null)
         el.className     = classname;
}

function k_hilite_feature (el,autoscroll) {
    k_dohilite(el,true,autoscroll);
}

function k_unhilite_feature (el) {
    k_dohilite(el,false,false);
}

