drop index featureloc_idx1;
drop index featureloc_idx2;
drop index featureloc_idx3;

alter table featureloc add column fmin int;
alter table featureloc add column fmax int;
update featureloc set fmin=nbeg where strand=1;
update featureloc set fmax=nend where strand=1;
update featureloc set fmax=nbeg where strand=-1;
update featureloc set fmin=nend where strand=-1;
update featureloc set fmin=nbeg where (strand=0 or strand is null) and nbeg<nend;
update featureloc set fmax=nend where (strand=0 or strand is null) and nbeg<nend;
update featureloc set fmin=nend where (strand=0 or strand is null) and nbeg>nend;
update featureloc set fmax=nbeg where (strand=0 or strand is null) and nbeg>nend;
create index featureloc_src_min_max on featureloc (srcfeature_id,fmin,fmax);

CREATE INDEX featureloc_idx1 ON featureloc USING btree (feature_id);
CREATE INDEX featureloc_idx2 ON featureloc USING btree (srcfeature_id);
CREATE INDEX featureloc_idx3 ON featureloc USING btree (srcfeature_id, nbeg, nend);

INSERT INTO featureloc (feature_id, fmin, fmax, srcfeature_id)
 SELECT DISTINCT hit.feature_id,
                  min(hsploc1.fmin), max(hsploc2.fmax),
                  min(hsploc1.srcfeature_id)
  FROM
    feature AS hit
      INNER JOIN
    feature_relationship       ON (hit.feature_id = objfeature_id)
      INNER JOIN
    featureloc AS hsploc1      ON (hsploc1.feature_id = subjfeature_id)
      INNER JOIN
    featureloc AS hsploc2      ON (hsploc2.feature_id = subjfeature_id)
  WHERE hit.type_id in (select cvterm_id from cvterm where name = 'alignment_hit') 
    AND hsploc1.rank = 0
    AND hsploc2.rank = 0
  GROUP BY hit.feature_id;

CREATE TABLE gbrowse_assembly AS SELECT * FROM feature WHERE type_id in
  (SELECT cvterm_id FROM cvterm WHERE name = 'chromosome_arm');
