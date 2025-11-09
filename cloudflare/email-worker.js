/**
 * Cloudflare Email Worker for Loomio
 *
 * This worker receives incoming emails via Cloudflare Email Routing
 * and forwards them to the Loomio email processor endpoint.
 *
 * Setup:
 * 1. Deploy this worker to Cloudflare
 * 2. Set WEBHOOK_URL environment variable to: https://loomio.lyckbo.de/email_processor/
 * 3. Configure Email Routing to route emails to this worker
 */

export default {
  async email(message, env, ctx) {
    // Get webhook URL from environment variable
    const webhookUrl = env.WEBHOOK_URL || 'https://loomio.lyckbo.de/email_processor/';

    try {
      // Read the raw email content
      const rawEmail = await new Response(message.raw).text();

      // Prepare the payload for Loomio
      // Loomio expects the raw email in multipart/form-data format
      const formData = new FormData();

      // Add email metadata
      formData.append('from', message.from);
      formData.append('to', message.to);
      formData.append('subject', message.headers.get('subject') || '');

      // Add raw email as a text field
      formData.append('email', rawEmail);

      // Get message-id for tracking
      const messageId = message.headers.get('message-id') || '';
      formData.append('message-id', messageId);

      console.log(`Processing email from ${message.from} to ${message.to}, subject: ${message.headers.get('subject')}`);

      // Forward to Loomio's email processor with authentication
      const response = await fetch(webhookUrl, {
        method: 'POST',
        headers: {
          // Add authentication header to verify the request is from our worker
          'X-Email-Token': env.EMAIL_PROCESSOR_TOKEN || '',
        },
        body: formData,
      });

      if (response.ok) {
        console.log(`✅ Email forwarded successfully to Loomio (status: ${response.status})`);
      } else {
        const errorText = await response.text();
        console.error(`❌ Webhook failed with status ${response.status}: ${errorText}`);
      }

      // Always forward the email even if webhook fails
      // This ensures users still get email notifications
      await message.forward(env.FALLBACK_EMAIL || message.to);

    } catch (error) {
      console.error('❌ Error processing email:', error);

      // On error, reject the email with a message
      await message.setReject(`Email processing failed: ${error.message}`);
    }
  }
}
