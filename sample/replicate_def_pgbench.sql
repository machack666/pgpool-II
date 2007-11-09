-- $Header: /cvsroot/pgpool/pgpool-II/sample/replicate_def_pgbench.sql,v 1.1 2007/11/09 06:09:36 y-mori Exp $

INSERT INTO pgpool_catalog.replicate_def VALUES (
    'bench_parallel',
    'public',
    'branches',
    ARRAY['bid', 'bbalance', 'filler'],
    ARRAY['integer', 'integer', 'character(88)']
);

INSERT INTO pgpool_catalog.dist_def VALUES (
    'bench_parallel',
    'public',
    'tellers',
    ARRAY['tid', 'bid', 'tbalance', 'filler'],
    ARRAY['integer', 'integer', 'integer', 'character(84)']
);

