-- Fix orders RLS to allow anonymous buyers to place orders
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;

-- Drop existing insert policy if any and recreate
DROP POLICY IF EXISTS "anon places orders" ON public.orders;
DROP POLICY IF EXISTS "anyone can place orders" ON public.orders;

-- Allow ALL roles (anon, authenticated) to insert orders
CREATE POLICY "anyone can place orders"
  ON public.orders
  FOR INSERT
  TO anon, authenticated
  WITH CHECK (true);

-- Allow store owners to read and update their orders
DROP POLICY IF EXISTS "store owners read orders" ON public.orders;
CREATE POLICY "store owners read orders"
  ON public.orders
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.stores
      WHERE id = store_id AND owner_id = auth.uid()
    )
    OR auth.uid() = promoter_id
  );

DROP POLICY IF EXISTS "store owners update orders" ON public.orders;
CREATE POLICY "store owners update orders"
  ON public.orders
  FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.stores
      WHERE id = store_id AND owner_id = auth.uid()
    )
  );

SELECT 'Orders RLS fixed ✓' AS status;
