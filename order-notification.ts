import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY')!
const SUPABASE_URL   = Deno.env.get('SUPABASE_URL')!
const SUPABASE_KEY   = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

serve(async (req) => {
  try {
    const payload = await req.json()
    const order   = payload.record
    if (!order) return new Response('No order', { status: 400 })

    const supabase = createClient(SUPABASE_URL, SUPABASE_KEY)

    // Get store + owner_id
    const { data: store } = await supabase
      .from('stores')
      .select('name, owner_id')
      .eq('id', order.store_id)
      .single()

    if (!store) return new Response('Store not found', { status: 200 })

    // Get agent profile separately
    const { data: profile } = await supabase
      .from('profiles')
      .select('email, full_name')
      .eq('id', store.owner_id)
      .single()

    // Get product name
    const { data: product } = await supabase
      .from('products')
      .select('name')
      .eq('id', order.product_id)
      .single()

    const agentEmail  = profile?.email
    const agentName   = profile?.full_name || 'Agent'
    const storeName   = store.name
    const productName = product?.name || 'Product'

    if (!agentEmail) return new Response('No agent email found', { status: 200 })

    // Send email via Resend
    const emailRes = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${RESEND_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: 'CityShop Orders <onboarding@resend.dev>',
        to: agentEmail,
        subject: `🛍️ New Order! ${productName} — GH₵ ${order.total}`,
        html: `
          <div style="font-family:Inter,sans-serif;max-width:600px;margin:0 auto;background:#0f0e1a;color:#fff;border-radius:16px;overflow:hidden;">
            <div style="background:#EF4444;padding:24px 32px;">
              <h1 style="margin:0;font-size:1.4rem;">🛍️ New Order Received!</h1>
              <p style="margin:4px 0 0;opacity:0.85;">${storeName}</p>
            </div>
            <div style="padding:32px;">
              <table style="width:100%;border-collapse:collapse;">
                <tr style="border-bottom:1px solid rgba(255,255,255,0.1);">
                  <td style="padding:10px 0;color:rgba(255,255,255,0.5);font-size:0.85rem;">Order Ref</td>
                  <td style="padding:10px 0;font-weight:700;text-align:right;">${order.ref}</td>
                </tr>
                <tr style="border-bottom:1px solid rgba(255,255,255,0.1);">
                  <td style="padding:10px 0;color:rgba(255,255,255,0.5);font-size:0.85rem;">Product</td>
                  <td style="padding:10px 0;font-weight:600;text-align:right;">${productName} × ${order.quantity}</td>
                </tr>
                <tr style="border-bottom:1px solid rgba(255,255,255,0.1);">
                  <td style="padding:10px 0;color:rgba(255,255,255,0.5);font-size:0.85rem;">Buyer</td>
                  <td style="padding:10px 0;text-align:right;">${order.buyer_name}</td>
                </tr>
                <tr style="border-bottom:1px solid rgba(255,255,255,0.1);">
                  <td style="padding:10px 0;color:rgba(255,255,255,0.5);font-size:0.85rem;">Phone</td>
                  <td style="padding:10px 0;text-align:right;">${order.buyer_phone}</td>
                </tr>
                <tr style="border-bottom:1px solid rgba(255,255,255,0.1);">
                  <td style="padding:10px 0;color:rgba(255,255,255,0.5);font-size:0.85rem;">City</td>
                  <td style="padding:10px 0;text-align:right;">${order.buyer_city || 'Not specified'}</td>
                </tr>
                <tr style="border-bottom:1px solid rgba(255,255,255,0.1);">
                  <td style="padding:10px 0;color:rgba(255,255,255,0.5);font-size:0.85rem;">Fulfillment</td>
                  <td style="padding:10px 0;text-align:right;">${order.fulfillment}</td>
                </tr>
                <tr style="border-bottom:1px solid rgba(255,255,255,0.1);">
                  <td style="padding:10px 0;color:rgba(255,255,255,0.5);font-size:0.85rem;">Payment</td>
                  <td style="padding:10px 0;text-align:right;">${order.payment_method === 'paystack' ? '✅ Paid Online' : '💬 WhatsApp / On Delivery'}</td>
                </tr>
                <tr>
                  <td style="padding:16px 0 0;font-size:1.1rem;font-weight:700;">Total</td>
                  <td style="padding:16px 0 0;font-size:1.1rem;font-weight:700;color:#EF4444;text-align:right;">GH₵ ${order.total}</td>
                </tr>
              </table>
              ${order.buyer_address ? `
              <div style="margin-top:20px;padding:14px;background:rgba(255,255,255,0.05);border-radius:10px;">
                <p style="margin:0;font-size:0.8rem;color:rgba(255,255,255,0.5);">Delivery Address</p>
                <p style="margin:4px 0 0;">${order.buyer_address}</p>
              </div>` : ''}
              <div style="margin-top:28px;text-align:center;">
                <a href="https://cityshop-web.vercel.app/dashboard-agent.html"
                  style="background:#EF4444;color:#fff;padding:12px 28px;border-radius:10px;text-decoration:none;font-weight:600;display:inline-block;">
                  View Order in Dashboard →
                </a>
              </div>
              <p style="margin-top:24px;font-size:0.75rem;color:rgba(255,255,255,0.3);text-align:center;">
                City Shop Ghana · You received this because you have an active store
              </p>
            </div>
          </div>
        `,
      }),
    })

    const result = await emailRes.json()
    console.log('Email sent:', JSON.stringify(result))
    return new Response(JSON.stringify({ success: true, result }), {
      headers: { 'Content-Type': 'application/json' },
    })

  } catch (err) {
    console.error('Error:', String(err))
    return new Response(JSON.stringify({ error: String(err) }), { status: 500 })
  }
})
