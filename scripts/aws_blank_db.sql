do
$$
declare
  l_stmt text;
begin
  select 'drop table ' || string_agg(format('%I.%I', schemaname, tablename), ',')
    into l_stmt
  from pg_tables
  where schemaname in ('public');

  execute l_stmt;
end;
$$;
SELECT * FROM pg_namespace where nspname='public'; -- Then use the value from pg_namespace
do
$$
declare
  l_stmt text;
begin
  select 'drop event trigger ' || string_agg(format('%I', evtname), ',')
    into l_stmt
  from pg_event_trigger;

  execute l_stmt;
end;
$$;
do
$$
declare
  l_stmt text;
begin
  select 'drop extension ' || string_agg(format('%I', extname), ',')
    into l_stmt
  from pg_extension
   WHERE  extnamespace = 2200  -- see above
  ;

  execute l_stmt;
end;
$$;

do
$$
DECLARE
  l_stmt text;
BEGIN
  SELECT string_agg(format('DROP %s %s;'
                          , CASE prokind
                              WHEN 'f' THEN 'FUNCTION'
                              WHEN 'a' THEN 'AGGREGATE'
                              WHEN 'p' THEN 'PROCEDURE'
                              WHEN 'w' THEN 'FUNCTION'  -- window function (rarely applicable)
                              -- ELSE NULL              -- not possible in pg 11
                            END
                          , oid::regprocedure)
                   , E'\n')
          INTO l_stmt
   FROM   pg_proc
   WHERE  pronamespace = 2200  -- see above
    AND    prokind = ANY ('{f,a,p,w}')         -- optionally filter kinds
   ;
   execute l_stmt;
END
$$;

do
$$
declare
  l_stmt text;
begin
  select 'drop type ' || string_agg(format('%I', typname), ',')
    into l_stmt
  from pg_type
   WHERE  typnamespace = 2200  -- see above
  ;

  execute l_stmt;
end;
$$;
