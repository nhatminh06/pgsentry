-- pgsafe: ignore PGSAFE001 reason="small table, approved maintenance window"
CREATE INDEX idx_small_code ON public.small_lookup(code);
