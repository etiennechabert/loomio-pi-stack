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

/**
 * Decode RFC 2047 encoded email headers (e.g., subjects with non-ASCII characters)
 * Format: =?charset?encoding?encoded-text?=
 * Examples:
 *   =?UTF-8?Q?R=C3=A9pondre?= -> Répondre
 *   =?UTF-8?B?UmVzcG9uZHJl?= -> Respondre
 */
function decodeRFC2047(str) {
  if (!str) return str;

  // Match pattern: =?charset?encoding?encoded-text?=
  const rfc2047Pattern = /=\?([^?]+)\?([QqBb])\?([^?]*)\?=/g;

  return str.replace(rfc2047Pattern, (match, charset, encoding, encodedText) => {
    try {
      let bytes;

      if (encoding.toUpperCase() === 'Q') {
        // Quoted-printable: decode =XX to bytes, replace _ with space
        const text = encodedText.replace(/_/g, ' ');
        const byteArray = [];

        for (let i = 0; i < text.length; i++) {
          if (text[i] === '=' && i + 2 < text.length) {
            // Decode =XX to byte
            const hex = text.substring(i + 1, i + 3);
            byteArray.push(parseInt(hex, 16));
            i += 2; // Skip the two hex digits
          } else {
            // Regular ASCII character
            byteArray.push(text.charCodeAt(i));
          }
        }

        bytes = new Uint8Array(byteArray);
      } else if (encoding.toUpperCase() === 'B') {
        // Base64 decode to byte array
        const binaryString = atob(encodedText);
        bytes = new Uint8Array(binaryString.length);
        for (let i = 0; i < binaryString.length; i++) {
          bytes[i] = binaryString.charCodeAt(i);
        }
      } else {
        return match; // Unknown encoding, return as-is
      }

      // Decode bytes as UTF-8
      const decoder = new TextDecoder(charset.toLowerCase());
      return decoder.decode(bytes);
    } catch (e) {
      console.error(`Failed to decode RFC 2047 header: ${match}`, e);
      return match; // Return original on error
    }
  });
}

export default {
  async email(message, env, ctx) {
    // Use ActionMailbox relay ingress instead of legacy /email_processor
    // This endpoint accepts raw email and Rails Mail library handles all parsing
    const webhookUrl = env.WEBHOOK_URL || 'https://loomio.lyckbo.de/rails/action_mailbox/relay/inbound_emails';

    try {
      // Get raw email - send to ActionMailbox relay ingress
      // Rails Mail library will handle all parsing (MIME, attachments, encoding, etc.)
      const rawEmail = await new Response(message.raw).arrayBuffer();

      const rawSubject = message.headers.get('subject');
      const decodedSubject = decodeRFC2047(rawSubject);
      console.log(`Processing email from ${message.from} to ${message.to}, subject: ${decodedSubject}`);

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
