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
    // Get webhook URL from environment variable (set during deployment)
    const webhookUrl = env.WEBHOOK_URL;

    try {
      // Convert headers to object for Loomio
      const headersObj = {};
      for (const [key, value] of message.headers) {
        headersObj[key] = value;
      }

      // Get raw email and extract text/html parts
      const rawEmail = await new Response(message.raw).text();

      // Simple MIME parser to extract text and HTML parts
      let textBody = '';
      let htmlBody = '';
      const attachments = [];

      // Decode quoted-printable
      const decodeQuotedPrintable = (str) => {
        return str
          .replace(/=\r?\n/g, '') // Remove soft line breaks
          .replace(/=([0-9A-F]{2})/gi, (_, hex) => String.fromCharCode(parseInt(hex, 16)));
      };

      // Check if multipart
      const contentType = message.headers.get('content-type') || '';
      if (contentType.includes('multipart')) {
        // Extract boundary
        const boundaryMatch = contentType.match(/boundary="?([^";\s]+)"?/);
        if (boundaryMatch) {
          const boundary = boundaryMatch[1];
          const parts = rawEmail.split(`--${boundary}`);

          for (const part of parts) {
            if (part.includes('Content-Type: text/plain')) {
              // Find the double newline that separates headers from body
              const bodyStart = part.search(/\r?\n\r?\n/);
              if (bodyStart !== -1) {
                let body = part.substring(bodyStart + 2).trim();
                // Remove trailing boundary
                body = body.replace(/\r?\n?--[^\r\n]*--?\s*$/, '').trim();
                // Decode if quoted-printable
                if (part.includes('Content-Transfer-Encoding: quoted-printable')) {
                  body = decodeQuotedPrintable(body);
                }
                textBody = body;
              }
            }
            if (part.includes('Content-Type: text/html')) {
              // Find the double newline that separates headers from body
              const bodyStart = part.search(/\r?\n\r?\n/);
              if (bodyStart !== -1) {
                let body = part.substring(bodyStart + 2).trim();
                // Remove trailing boundary
                body = body.replace(/\r?\n?--[^\r\n]*--?\s*$/, '').trim();
                // Decode if quoted-printable
                if (part.includes('Content-Transfer-Encoding: quoted-printable')) {
                  body = decodeQuotedPrintable(body);
                }
                htmlBody = body;
              }
            }
          }
        }
      } else {
        // Plain text email - split at first double newline
        const parts = rawEmail.split(/\r?\n\r?\n/);
        textBody = parts.slice(1).join('\n\n').trim();
        if (contentType.includes('quoted-printable')) {
          textBody = decodeQuotedPrintable(textBody);
        }
      }

      // Create mailinMsg format that Loomio expects
      const mailinData = {
        headers: headersObj,
        text: textBody || rawEmail, // Fallback to raw if parsing fails
        html: htmlBody,
        attachments: []
      };

      // Prepare form data
      const formData = new FormData();
      formData.append('mailinMsg', JSON.stringify(mailinData));

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
