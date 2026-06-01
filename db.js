// ============================================================
// db.js — City Shop · Central Supabase Engine
// Import this module into every HTML page via:
//   import { ... } from './db.js';
// ============================================================
import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js/+esm';

// ── ⚠ Replace these with your actual Supabase project values ─
export const SUPABASE_URL      = 'https://pehvrvgptplowukdgone.supabase.co';
export const SUPABASE_ANON_KEY = 'sb_publishable_9tOFD1hgehzp6woo0w-5-g_CAYZSvtN';
// ─────────────────────────────────────────────────────────────

export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

// ============================================================
// AUTH
// ============================================================

/** Sign up a new user, create their profile row, and (if agent) auto-create a store. */
export async function signUp(email, password, role, fullName) {
  // Pass role and full_name as metadata so the DB trigger can read them
  const { data, error } = await supabase.auth.signUp({
    email,
    password,
    options: {
      data: { full_name: fullName, role }
    }
  });
  if (error) throw error;

  const userId = data.user.id;

  // Wait a moment for the trigger to create the profile row
  await new Promise(r => setTimeout(r, 800));

  // Update profile with full details (trigger may only set basics)
  const { error: profErr } = await supabase.from('profiles').upsert({
    id:                  userId,
    full_name:           fullName,
    email,
    role,
    subscription_active: false,
  });
  if (profErr) throw profErr;

  // Auto-create store for agents
  if (role === 'agent') {
    const baseSlug = fullName.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
    const slug     = `${baseSlug}-${Date.now().toString(36)}`;
    const { error: storeErr } = await supabase.from('stores').insert({
      owner_id:    userId,
      name:        `${fullName}'s Store`,
      slug,
      description: '',
      logo_url:    '',
      phone:       '',
      whatsapp:    '',
    });
    if (storeErr) throw storeErr;
  }

  return data;
}

/** Sign in with email + password. Returns { user, session }. */
export async function signIn(email, password) {
  const { data, error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) throw error;
  return data;
}

/** Sign out the current user. */
export async function signOut() {
  await supabase.auth.signOut();
}

/** Get the current active session (or null). */
export async function getSession() {
  const { data } = await supabase.auth.getSession();
  return data.session;
}

/** Fetch a user's profile row by their UUID. */
export async function getProfile(userId) {
  const { data, error } = await supabase
    .from('profiles')
    .select('*')
    .eq('id', userId)
    .single();
  if (error) throw error;
  return data;
}

/** Update a profile row. */
export async function updateProfile(userId, updates) {
  const { data, error } = await supabase
    .from('profiles')
    .update(updates)
    .eq('id', userId)
    .select()
    .single();
  if (error) throw error;
  return data;
}

/** Upload a profile avatar or banner. type = 'avatar' | 'banner' */
export async function uploadProfileMedia(file, userId, type) {
  const ext  = file.name.split('.').pop();
  const path = `profiles/${userId}-${type}.${ext}`;
  const { error: upErr } = await supabase.storage
    .from('PRODUCT-IMAGE')
    .upload(path, file, { upsert: true, contentType: file.type });
  if (upErr) throw upErr;
  const { data } = supabase.storage.from('PRODUCT-IMAGE').getPublicUrl(path);
  return data.publicUrl;
}

// ============================================================
// STORES
// ============================================================

/** Get the store owned by a specific user. */
export async function getStoreByOwner(userId) {
  const { data, error } = await supabase
    .from('stores')
    .select('*')
    .eq('owner_id', userId)
    .single();
  if (error) throw error;
  return data;
}

/** Get a store by its public slug. */
export async function getStoreBySlug(slug) {
  const { data, error } = await supabase
    .from('stores')
    .select('*')
    .eq('slug', slug)
    .single();
  if (error) throw error;
  return data;
}

/**
 * Single JOIN query: fetch store + all its products in one round-trip.
 * Replaces the old two-sequential-await pattern in store.html.
 */
export async function getStoreWithProducts(slugOrId) {
  // Support lookup by slug or by UUID (fallback for stores without slug)
  const isUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(slugOrId);
  let query = supabase
    .from('stores')
    .select('*, products(*)')
    .order('created_at', { ascending: false, foreignTable: 'products' });
  query = isUuid ? query.eq('id', slugOrId) : query.eq('slug', slugOrId);
  const { data, error } = await query.single();
  if (error) throw error;
  return { store: data, products: data.products ?? [] };
}

/** Get all active stores with their products (for discovery page). */
export async function getAllStores() {
  const { data, error } = await supabase
    .from('stores')
    .select('*, products(id, category, price)')
    .eq('is_active', true)
    .order('created_at', { ascending: false });
  if (error) throw error;
  return data ?? [];
}

/** Get all products across all active stores (for promoter browse). */
export async function getAllProducts() {
  const { data, error } = await supabase
    .from('products')
    .select('*, stores(id, name, slug, whatsapp, phone, logo_url, banner_url)')
    .eq('in_stock', true)
    .order('created_at', { ascending: false });
  if (error) throw error;
  return data ?? [];
}

/** Update store fields. Returns the updated store row. */
export async function updateStore(storeId, updates) {
  const { data, error } = await supabase
    .from('stores')
    .update(updates)
    .eq('id', storeId)
    .select()
    .single();
  if (error) throw error;
  return data;
}

/** Check whether a slug is already taken (excluding the current store). */
export async function isSlugAvailable(slug, excludeStoreId = null) {
  let query = supabase
    .from('stores')
    .select('id', { count: 'exact', head: true })
    .eq('slug', slug.toLowerCase());
  if (excludeStoreId) query = query.neq('id', excludeStoreId);
  const { count, error } = await query;
  if (error) throw error;
  return count === 0;
}


// ============================================================
// STORAGE — Image Uploads
// ============================================================

/**
 * Upload a product image file to Supabase Storage.
 * Returns the public URL of the uploaded image.
 */
export async function uploadProductImage(file, storeId) {
  const ext      = file.name.split('.').pop().toLowerCase();
  const allowed  = ['jpg','jpeg','png','webp','gif'];
  if (!allowed.includes(ext)) throw new Error('Only JPG, PNG, WEBP, or GIF images are allowed.');
  if (file.size > 5 * 1024 * 1024) throw new Error('Image must be smaller than 5MB.');

  const fileName = `${storeId}/${Date.now()}-${Math.random().toString(36).slice(2)}.${ext}`;

  const { error } = await supabase.storage
    .from('PRODUCT-IMAGE')
    .upload(fileName, file, { upsert: false, contentType: file.type });

  if (error) throw error;

  const { data } = supabase.storage
    .from('PRODUCT-IMAGE')
    .getPublicUrl(fileName);

  return data.publicUrl;
}

// ============================================================
// PRODUCTS
// ============================================================

/** Add a new product to a store. */
export async function addProduct(storeId, name, price, imageUrl, description, category, wholesalePrice = null) {
  const { data, error } = await supabase
    .from('products')
    .insert({
      store_id:        storeId,
      name,
      price,
      wholesale_price: wholesalePrice,
      image_url:       imageUrl || '',
      description:     description || '',
      category:        category || '',
    })
    .select()
    .single();
  if (error) throw error;
  return data;
}

/** Update an existing product. */
export async function updateProduct(productId, updates) {
  const { data, error } = await supabase
    .from('products')
    .update(updates)
    .eq('id', productId)
    .select()
    .single();
  if (error) throw error;
  return data;
}

/** Get all products for a specific store (newest first). */
export async function getProductsByStore(storeId) {
  const { data, error } = await supabase
    .from('products')
    .select('*')
    .eq('store_id', storeId)
    .order('created_at', { ascending: false });
  if (error) throw error;
  return data;
}

/** Record a promoter link click. */
export async function trackClick(promoterId, productId) {
  const { error } = await supabase
    .from('link_clicks')
    .insert({ promoter_id: promoterId, product_id: productId });
  if (error) console.warn('Click track failed:', error.message);
}

/** Get click counts for a promoter. */
export async function getClicksByPromoter(promoterId) {
  const { data, error } = await supabase
    .from('link_clicks')
    .select('product_id, products(name)')
    .eq('promoter_id', promoterId);
  if (error) throw error;
  return data ?? [];
}

/** Delete a product by ID. */
export async function deleteProduct(productId) {
  const { error } = await supabase.from('products').delete().eq('id', productId);
  if (error) throw error;
}

// ============================================================
// SUBSCRIPTIONS
// ============================================================

/** Mark a user's subscription as active and record the Paystack ref. */
export async function activateSubscription(userId, paystackRef = '') {
  const end = new Date();
  end.setDate(end.getDate() + 30); // 30-day subscription

  const { error } = await supabase
    .from('profiles')
    .update({
      subscription_active: true,
      subscription_end:    end.toISOString(),
      paystack_ref:        paystackRef,
    })
    .eq('id', userId);
  if (error) throw error;
}

// ============================================================
// WITHDRAWALS
// ============================================================

/** Submit a withdrawal request. */
export async function submitWithdrawal(userId, role, { fullName, email, network, momoNumber, amount }) {
  const { data, error } = await supabase
    .from('withdrawals')
    .insert({
      user_id:    userId,
      role,
      full_name:  fullName,
      email,
      network,
      momo_number: momoNumber,
      amount,
      status:     'pending',
    })
    .select()
    .single();
  if (error) throw error;
  return data;
}

/** Get all withdrawals for a user. */
export async function getWithdrawals(userId) {
  const { data, error } = await supabase
    .from('withdrawals')
    .select('*')
    .eq('user_id', userId)
    .order('created_at', { ascending: false });
  if (error) throw error;
  return data;
}

// ============================================================
// ORDERS
// ============================================================

/** Generate a human-readable order reference e.g. CS-20240312-A3F2 */
function generateOrderRef() {
  const d   = new Date();
  const date = `${d.getFullYear()}${String(d.getMonth()+1).padStart(2,'0')}${String(d.getDate()).padStart(2,'0')}`;
  const rand = Math.random().toString(36).substring(2,6).toUpperCase();
  return `CS-${date}-${rand}`;
}

/** Place a new order (guest — no auth required). */
export async function placeOrder({ storeId, productId, promoterId = null,
  buyerName, buyerPhone, buyerAddress, buyerCity,
  quantity, basePrice, markup, deliveryFee, total,
  fulfillment, paymentMethod, paystackRef = '' }) {
  const ref = generateOrderRef();
  const { error } = await supabase
    .from('orders')
    .insert({
      ref, store_id: storeId, product_id: productId, promoter_id: promoterId,
      buyer_name: buyerName, buyer_phone: buyerPhone,
      buyer_address: buyerAddress, buyer_city: buyerCity,
      quantity, base_price: basePrice, markup, delivery_fee: deliveryFee, total,
      fulfillment, payment_method: paymentMethod, paystack_ref: paystackRef,
    });
  if (error) throw error;
  // Return a local object so the receipt can render without needing a SELECT
  return {
    ref, store_id: storeId, product_id: productId, promoter_id: promoterId,
    buyer_name: buyerName, buyer_phone: buyerPhone,
    buyer_address: buyerAddress, buyer_city: buyerCity,
    quantity, base_price: basePrice, markup, delivery_fee: deliveryFee, total,
    fulfillment, payment_method: paymentMethod, paystack_ref: paystackRef,
  };
}

/** Get all orders for a store (agent view). */
export async function getOrdersByStore(storeId) {
  const { data, error } = await supabase
    .from('orders')
    .select('*, products(name, image_url)')
    .eq('store_id', storeId)
    .order('created_at', { ascending: false });
  if (error) throw error;
  return data;
}

/** Update order status. */
export async function updateOrderStatus(orderId, status, note = '') {
  const { data, error } = await supabase
    .from('orders')
    .update({ status, note })
    .eq('id', orderId)
    .select()
    .single();
  if (error) throw error;
  return data;
}

/** Get orders referred by a promoter. */
export async function getOrdersByPromoter(promoterId) {
  const { data, error } = await supabase
    .from('orders')
    .select('*, products(name), stores(name)')
    .eq('promoter_id', promoterId)
    .order('created_at', { ascending: false });
  if (error) throw error;
  return data;
}

/** Listen for new orders on a store in realtime. */
export function listenToOrders(storeId, callback) {
  return supabase
    .channel(`orders:${storeId}`)
    .on('postgres_changes', {
      event: 'INSERT', schema: 'public', table: 'orders',
      filter: `store_id=eq.${storeId}`
    }, callback)
    .subscribe();
}

// ============================================================
// REVIEWS
// ============================================================

/** Submit a new review for a product. */
export async function submitReview({ productId, storeId, orderId = null,
  buyerName, rating, body, verified = false }) {
  const { data, error } = await supabase
    .from('reviews')
    .insert({ product_id: productId, store_id: storeId, order_id: orderId,
      buyer_name: buyerName, rating, body, verified })
    .select()
    .single();
  if (error) throw error;
  return data;
}

/** Get all reviews for a product (newest first). */
export async function getReviewsByProduct(productId) {
  const { data, error } = await supabase
    .from('reviews')
    .select('*')
    .eq('product_id', productId)
    .order('created_at', { ascending: false });
  if (error) throw error;
  return data;
}

/** Get all reviews for a store. */
export async function getReviewsByStore(storeId) {
  const { data, error } = await supabase
    .from('reviews')
    .select('*, products(name)')
    .eq('store_id', storeId)
    .order('created_at', { ascending: false });
  if (error) throw error;
  return data;
}

/** Get average rating + count for a store. */
export async function getStoreRating(storeId) {
  const { data, error } = await supabase
    .from('reviews')
    .select('rating')
    .eq('store_id', storeId);
  if (error) throw error;
  if (!data?.length) return { avg: 0, count: 0 };
  const avg = data.reduce((s, r) => s + r.rating, 0) / data.length;
  return { avg: Math.round(avg * 10) / 10, count: data.length };
}

/** Agent reply to a review. */
export async function replyToReview(reviewId, reply) {
  const { data, error } = await supabase
    .from('reviews')
    .update({ reply, replied_at: new Date().toISOString() })
    .eq('id', reviewId)
    .select()
    .single();
  if (error) throw error;
  return data;
}

// ============================================================
// REALTIME
// ============================================================

/**
 * Subscribe to live product changes for a given store.
 * @param {string}   storeId  - The store UUID to watch
 * @param {function} callback - Called with Supabase payload on every change
 * @returns Supabase channel (call .unsubscribe() on cleanup)
 */
export function listenToProducts(storeId, callback) {
  return supabase
    .channel(`products:store_${storeId}`)
    .on(
      'postgres_changes',
      {
        event:  '*',
        schema: 'public',
        table:  'products',
        filter: `store_id=eq.${storeId}`,
      },
      callback
    )
    .subscribe();
}

// ═══════════════════════════════════════════════════════════════
// PRODUCT MEDIA — 5 images + 1 video
// ═══════════════════════════════════════════════════════════════

export async function uploadProductMedia(file, storeId, mediaType = 'image') {
  const ext = file.name.split('.').pop().toLowerCase();
  const allowedImages = ['jpg','jpeg','png','webp','gif'];
  const allowedVideos = ['mp4','mov','avi','webm'];

  if (mediaType === 'image') {
    if (!allowedImages.includes(ext)) throw new Error('Only JPG, PNG, WEBP, or GIF images are allowed.');
    if (file.size > 5 * 1024 * 1024) throw new Error('Image must be smaller than 5MB.');
  } else if (mediaType === 'video') {
    if (!allowedVideos.includes(ext)) throw new Error('Only MP4, MOV, AVI, or WEBM videos are allowed.');
    if (file.size > 50 * 1024 * 1024) throw new Error('Video must be smaller than 50MB.');
  }

  const folder = mediaType === 'image' ? 'images' : 'videos';
  const fileName = `${storeId}/${folder}/${Date.now()}-${Math.random().toString(36).slice(2)}.${ext}`;

  const { error } = await supabase.storage
    .from('PRODUCT-IMAGE')
    .upload(fileName, file, { upsert: false, contentType: file.type });

  if (error) throw error;

  const { data } = supabase.storage
    .from('PRODUCT-IMAGE')
    .getPublicUrl(fileName);

  return data.publicUrl;
}

export async function addProductMedia(productId, mediaType, mediaUrl, sortOrder = 0) {
  const { data, error } = await supabase
    .from('product_media')
    .insert({ product_id: productId, media_type: mediaType, media_url: mediaUrl, sort_order: sortOrder })
    .select().single();
  if (error) throw error;
  return data;
}

export async function getProductMedia(productId) {
  const { data, error } = await supabase
    .from('product_media')
    .select('*')
    .eq('product_id', productId)
    .order('sort_order', { ascending: true });
  if (error) throw error;
  return data || [];
}

export async function deleteProductMedia(mediaId) {
  const { error } = await supabase.from('product_media').delete().eq('id', mediaId);
  if (error) throw error;
  return true;
}
