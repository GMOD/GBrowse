// helper utilities for the karyotype module.

function k_dohilite (base_id,hilite_it,autoscroll) {
    var graphical_feature = $("box_"    + base_id);
    var text_feature      = $("feature_"+ base_id)
    var classname         = hilite_it ? 'hilite' : 'nohilite';

    if (graphical_feature) {
        graphical_feature.className=classname;
    }

    if (text_feature) {
         text_feature.className=classname;
         var top = text_feature.positionedOffset().top;
         if (autoscroll)
          $('scrolling_table').scrollTop = top;
    }
}

function k_hilite_feature (base_id,autoscroll) {
    k_dohilite(base_id,true,autoscroll);
}

function k_unhilite_feature (base_id) {
    k_dohilite(base_id,false,false);
}
