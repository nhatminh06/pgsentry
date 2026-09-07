SET lock_timeout = '2s';
CREATE INDEX CONCURRENTLY idx_orders_customer ON public.orders(customer_id);
ALTER TABLE public.orders ADD CONSTRAINT orders_total_positive CHECK (total >= 0) NOT VALID;
ALTER TABLE public.orders VALIDATE CONSTRAINT orders_total_positive;
ALTER TABLE public.orders ADD CONSTRAINT orders_customer_fk FOREIGN KEY (customer_id) REFERENCES public.customers(id) NOT VALID;
ALTER TABLE public.orders ADD COLUMN archived boolean DEFAULT false;
UPDATE public.orders SET archived = true WHERE archived_at IS NOT NULL;
DELETE FROM public.orders WHERE deleted_at < current_date - 90;
