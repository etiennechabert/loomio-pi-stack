/**
 * Cloudflare Email Worker for Loomio
 *
 * This worker receives incoming emails via Cloudflare Email Routing
 * and forwards them to the Loomio email processor endpoint.
 *
 * Setup:
 * 1. Deploy this worker to Cloudflare using: make deploy-email-worker
 * 2. The script automatically configures WEBHOOK_URL and EMAIL_PROCESSOR_TOKEN
 * 3. Configure Email Routing to route emails to this worker
 */

export default {
  async email(message, env, ctx) {
    // Use ActionMailbox relay ingress instead of legacy /email_processor
    // This endpoint accepts raw email and Rails Mail library handles all parsing
    const webhookUrl = env.WEBHOOK_URL || 'https://loomio.lyckbo.de/rails/action_mailbox/relay/inbound_emails';

    try {
      // Get raw email - send to ActionMailbox relay ingress
      // Rails Mail library will handle all parsing (MIME, attachments, encoding, etc.)
      const rawEmail = await new Response(message.raw).arrayBuffer();

      console.log(`Processing email from ${message.from} to ${message.to}, subject: ${message.headers.get('subject')}`);

      // Send raw email to ActionMailbox relay ingress
      // Format: multipart/form-data with 'message' field
      const formData = new FormData();
      formData.append('message', new Blob([rawEmail], { type: 'message/rfc822' }), 'email.eml');

      const response = await fetch(webhookUrl, {
        method: 'POST',
        headers: {
          // Optional: Add authentication if RAILS_INBOUND_EMAIL_PASSWORD is set
          // 'Authorization': `Bearer ${env.EMAIL_PROCESSOR_TOKEN || ''}`,
        },
        body: formData,
      });

      if (response.ok) {
        console.log(`✅ Email forwarded successfully to Loomio (status: ${response.status})`);
      } else {
        const errorText = await response.text();
        console.error(`❌ Webhook failed with status ${response.status}: ${errorText}`);
        // Reject the email if webhook fails
        await message.setReject(`Failed to process email: webhook returned ${response.status}`);
        return;
      }

      // Email processed successfully, no need to forward
      console.log('✅ Email processing complete');

    } catch (error) {
      console.error('❌ Error processing email:', error);

      // On error, reject the email with a message
      await message.setReject(`Email processing failed: ${error.message}`);
    }
  }
}
