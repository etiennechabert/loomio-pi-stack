# Your Data Privacy & Security Guide

*This guide explains how your Loomio instance protects your data and privacy in simple, non-technical terms.*

## 🔐 Key Points About Your Data

### Where Is Your Data Stored?

✅ **Your data stays on YOUR server**
- All your discussions, votes, and files are stored on the Raspberry Pi or server you control
- Nothing is sent to external Loomio servers
- You have complete ownership and control of your data

### Who Can Access Your Data?

✅ **Only people you authorize**
- System administrators (people with server access)
- Users you invite to your Loomio instance
- Members of groups they belong to can see those group discussions

❌ **Who CANNOT access your data**
- Loomio developers (unless you explicitly share for support)
- Other Loomio instances
- Search engines (private by default)
- Anyone without an account on your instance

## 🛡️ How Your Data Is Protected

### 1. Password Protection

**Your account is secured by:**
- Strong password requirements
- Encrypted password storage (passwords are never stored in readable form)
- Optional two-factor authentication for extra security

**Best practices for users:**
- Use a unique, strong password
- Don't share your login credentials
- Log out when using shared computers

### 2. Encrypted Backups

**Automatic protection against data loss:**
- Your data is backed up automatically every hour
- Backups are encrypted with military-grade encryption (AES-256)
- Even if someone steals a backup file, they cannot read it without the encryption key
- Backups are kept for 30 days locally

**What this means for you:**
- If something goes wrong, your data can be restored
- Your discussions and votes are safe even if hardware fails
- Encrypted backups mean your data is protected even when stored

### 3. Secure Communication

**All connections are protected:**
- When configured with HTTPS, all data between your browser and Loomio is encrypted
- Email notifications use secure SMTP connections
- Passwords are never sent via email

### 4. Access Control

**You control who sees what:**
- **Private Groups**: Only invited members can see discussions
- **Secret Groups**: Not even visible to non-members
- **Public Groups**: Optional, disabled by default in this setup
- **Invite-Only Registration**: Only administrators can add new users

## 📊 What Data Is Collected?

### Information Stored

✅ **Account Information**
- Name and email address you provide
- Profile picture (if uploaded)
- Language preference
- Notification settings

✅ **Activity Data**
- Discussions you create or participate in
- Votes and proposals
- Comments and reactions
- Files you upload
- Group memberships

✅ **Technical Data**
- Login times for security
- Basic browser information for compatibility
- IP addresses in system logs (for security and troubleshooting)

### Information NOT Collected

❌ **We DO NOT collect:**
- Personal data beyond what you provide
- Browsing history outside of Loomio
- Location tracking
- Marketing or advertising data
- Data for sale to third parties

## 🔄 Data Retention & Deletion

### How Long Is Data Kept?

- **Active accounts**: Data is kept as long as the account exists
- **Deleted content**: Removed immediately from view, purged from backups after 30 days
- **Closed accounts**: Can be deleted upon request
- **System logs**: Rotated after 30 days

### Your Rights

You have the right to:
- ✅ Export your data
- ✅ Delete your account
- ✅ Remove content you've created
- ✅ Leave groups at any time
- ✅ Control your notification preferences

## 🚨 Security Measures in Place

### Technical Safeguards

1. **Regular Updates**
   - Security patches applied automatically
   - Container images updated regularly
   - Monitoring for vulnerabilities

2. **Firewall Protection**
   - Only necessary ports are open
   - Protection against unauthorized access
   - Rate limiting to prevent abuse

3. **Monitoring**
   - System health monitoring
   - Alerts for unusual activity
   - Regular backup verification

### Physical Security

- Your server/Raspberry Pi should be in a secure location
- Only trusted administrators should have physical access
- Consider the security of your home or office network

## 🌍 Third-Party Services

### Services We Use (Optional)

Depending on configuration, your instance may use:

1. **Email Service** (Gmail, SendGrid, etc.)
   - Only for sending notifications
   - No email content is stored by these services
   - You control which email service to use

2. **Google Drive** (if configured)
   - Only for backup storage
   - Backups are encrypted before upload
   - Optional - you can keep backups local only

3. **Cloudflare** (if configured)
   - For secure access without exposing your server
   - Provides DDoS protection
   - No discussion content is stored by Cloudflare

### Services We DON'T Use

❌ **No analytics or tracking services**
❌ **No advertising networks**
❌ **No social media integration (unless you add it)**
❌ **No external AI or machine learning on your data**

## 👥 For Group Administrators

If you manage a group, you can:
- Control group privacy settings
- Manage member permissions
- Export group data
- Delete old discussions
- Set group description and guidelines

**Your responsibilities:**
- Only invite trusted members to private groups
- Regularly review membership
- Remove inactive or problematic users
- Keep group purpose clear

## 🆘 In Case of Security Concerns

### Warning Signs

Contact your system administrator immediately if you notice:
- 🚨 Unexpected login notifications
- 🚨 Content you didn't create
- 🚨 Changes to your settings you didn't make
- 🚨 Members in groups you don't recognize

### What Administrators Can Do

Your system administrator can:
- Reset passwords
- Review access logs
- Remove suspicious accounts
- Restore from backups if needed
- Update security settings

## 📋 Privacy Best Practices for Users

### Do's
- ✅ Use a strong, unique password
- ✅ Keep your email address up to date
- ✅ Log out from shared computers
- ✅ Report suspicious activity
- ✅ Think before sharing sensitive information

### Don'ts
- ❌ Share your password
- ❌ Click suspicious links in discussions
- ❌ Upload sensitive files without encryption
- ❌ Assume deleted content is immediately gone from all backups

## 🤝 Our Commitment

This Loomio instance is committed to:
- **Transparency**: You know where your data is and who can access it
- **Security**: Multiple layers of protection for your information
- **Privacy**: Your data is never sold or shared without permission
- **Control**: You decide what to share and with whom
- **Reliability**: Regular backups ensure your data is safe

## ❓ Frequently Asked Questions

### Q: Can anyone on the internet see our discussions?
**A:** No, unless you specifically create public groups (disabled by default). All discussions require login.

### Q: What happens if I delete something?
**A:** It's immediately hidden from view and will be permanently removed from backups after 30 days.

### Q: Is our data sold to advertisers?
**A:** Never. Your data stays on your server and is never monetized.

### Q: What if our server crashes?
**A:** Hourly automated backups mean we can restore your data quickly. Maximum data loss would be 1 hour of activity.

### Q: Can law enforcement access our data?
**A:** Only with proper legal authority and only from your system administrator. Loomio developers have no access to your instance.

### Q: How do I export my data?
**A:** Contact your system administrator who can export your discussions and votes.

### Q: What about GDPR compliance?
**A:** This setup provides tools for GDPR compliance (data export, deletion, etc.). Your organization must establish appropriate policies.

## 📞 Need Help?

For questions about:
- **Your data**: Contact your system administrator
- **Privacy settings**: Check group settings or ask group administrators
- **Security concerns**: Report immediately to your system administrator
- **This documentation**: Ask your technical team for clarification

---

*Remember: Your privacy and security are shared responsibilities. The system provides the tools, but everyone must use them wisely.*

*Last updated: November 2024*