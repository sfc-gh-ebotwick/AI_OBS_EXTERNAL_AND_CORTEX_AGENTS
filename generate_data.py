import csv
import random
import os
from datetime import datetime, timedelta

random.seed(42)
OUTPUT_DIR = os.path.dirname(os.path.abspath(__file__))

PRODUCTS = ["CloudStore Platform", "DataSync Pro", "SecureVault", "AnalyticsHub", "API Gateway"]
ISSUE_CATEGORIES = ["Login/Authentication", "Performance", "Billing", "Data Loss", "Integration", "Feature Request", "Configuration", "Security"]
PRIORITIES = ["Low", "Medium", "High", "Critical"]
STATUSES = ["Resolved", "Resolved", "Resolved", "Resolved", "Open", "In Progress", "Escalated"]
AGENT_NAMES = ["Sarah Chen", "Mike Rodriguez", "Priya Patel", "James Wilson", "Emma Thompson",
               "Carlos Garcia", "Aisha Johnson", "David Kim", "Rachel Foster", "Tom Martinez"]

ISSUE_TEMPLATES = {
    "Login/Authentication": [
        ("Customer unable to log in after password reset. MFA token not being accepted despite correct entry.",
         "Reset MFA configuration and re-enrolled the user. Cleared cached authentication tokens on the server side. Verified successful login after re-enrollment."),
        ("SSO integration failing with SAML assertion errors for enterprise account.",
         "Updated the SAML certificate that had expired. Reconfigured the IdP metadata URL and validated the assertion consumer service endpoint."),
        ("Account locked after multiple failed login attempts from automated scripts.",
         "Unlocked the account and worked with the customer to implement API key-based authentication for their automated workflows instead of password-based login."),
        ("Two-factor authentication codes arriving with significant delay making login impossible.",
         "Switched the customer from SMS-based 2FA to authenticator app-based TOTP. Verified time synchronization on the customer's device."),
    ],
    "Performance": [
        ("Dashboard loading times exceeding 30 seconds for reports with large datasets.",
         "Identified inefficient query patterns in custom dashboard widgets. Optimized the underlying queries and implemented result caching. Load times reduced to under 3 seconds."),
        ("API response times spiking during peak business hours causing timeouts in downstream systems.",
         "Analyzed traffic patterns and identified a misconfigured rate limiter. Adjusted connection pooling settings and enabled auto-scaling for the customer's tier."),
        ("Batch data import jobs timing out when processing files over 500MB.",
         "Increased the batch processing timeout limits and enabled chunked upload mode. Recommended splitting files into 100MB segments for optimal throughput."),
        ("Search functionality returning results very slowly across the entire organization's workspace.",
         "Rebuilt the search index which had become fragmented. Applied index optimization and increased the allocated search compute resources."),
    ],
    "Billing": [
        ("Customer charged twice for monthly subscription renewal.",
         "Confirmed duplicate charge in payment system. Issued immediate refund for the duplicate transaction and added a billing flag to prevent recurrence."),
        ("Usage-based charges not matching customer's internal tracking metrics.",
         "Audited the metering logs and found a discrepancy in how API calls were counted. Corrected the metering configuration and issued a credit adjustment."),
        ("Invoice showing charges for a plan tier the customer did not subscribe to.",
         "Identified a plan migration error during the last billing cycle. Corrected the subscription record, regenerated the invoice, and applied the price difference as credit."),
        ("Auto-renewal processed despite customer requesting cancellation two weeks prior.",
         "Found the cancellation request was logged but not processed due to a workflow error. Processed the cancellation, issued a full refund, and escalated the workflow bug to engineering."),
    ],
    "Data Loss": [
        ("Customer reports missing records in their database after a scheduled maintenance window.",
         "Investigated and found records were moved to an archive table during maintenance. Restored records to the primary table and adjusted the archival policy settings."),
        ("Accidental deletion of a shared workspace containing critical project files.",
         "Recovered the workspace from the 30-day soft-delete retention. Restored all files and permissions. Recommended enabling workspace deletion protection for critical workspaces."),
        ("Data synchronization failure resulted in partial data in the staging environment.",
         "Identified a network interruption during sync. Ran a full resynchronization and implemented checksum validation to detect partial transfers in the future."),
        ("Export job produced incomplete CSV files missing the last several thousand rows.",
         "Found a memory limit being hit during export serialization. Increased the export buffer size and re-ran the export job with verification checksums."),
    ],
    "Integration": [
        ("Webhook deliveries failing with 403 errors to customer's endpoint after infrastructure change.",
         "Customer had updated their firewall rules and forgot to whitelist our webhook IPs. Provided the updated IP range list and verified successful webhook delivery."),
        ("REST API returning inconsistent schema in responses breaking the customer's ETL pipeline.",
         "Identified a version mismatch where the customer was hitting both v2 and v3 endpoints. Consolidated all calls to v3 and provided migration guidance for deprecated fields."),
        ("Salesforce integration not syncing new contact records created in the last 48 hours.",
         "Found the Salesforce connected app token had expired. Re-authorized the integration and triggered a manual backfill for the missed sync window."),
        ("Custom middleware integration dropping events under high throughput conditions.",
         "Increased the event queue buffer size and implemented dead-letter queue processing. Added monitoring alerts for queue depth thresholds."),
    ],
    "Feature Request": [
        ("Customer requesting ability to export reports in PDF format with custom branding.",
         "Logged feature request FR-4521. Provided workaround using the API to generate HTML reports that can be converted to PDF with their branding. Escalated to product team."),
        ("Enterprise customer needs role-based dashboard access with granular permissions.",
         "Documented the detailed requirements and submitted to product backlog as high-priority item. Implemented a temporary solution using workspace-level access controls."),
        ("Request for real-time collaboration features in the report builder.",
         "Created feature request FR-4589. Shared the product roadmap timeline showing this feature planned for Q3. Offered early beta access when available."),
        ("Customer wants automated anomaly detection alerts on their key business metrics.",
         "Logged feature request FR-4602. Demonstrated how to set up threshold-based alerts as an interim solution using existing notification rules."),
    ],
    "Configuration": [
        ("Customer unable to configure custom email templates for automated notifications.",
         "Walked the customer through the template configuration API. Found their HTML template had unsupported CSS properties. Provided a compatible template library."),
        ("Environment variable configuration not persisting across application restarts.",
         "Identified the customer was setting variables at the session level instead of the environment level. Updated configuration to use persistent environment settings."),
        ("Role-based access control rules not being applied correctly to new team members.",
         "Found a caching issue with the RBAC policy engine. Cleared the policy cache, corrected the role hierarchy, and verified permissions for all affected users."),
        ("Custom domain SSL certificate configuration failing during the verification step.",
         "The customer's DNS CNAME record was pointing to an incorrect verification endpoint. Corrected the DNS entry and completed SSL certificate provisioning."),
    ],
    "Security": [
        ("Customer flagged suspicious login activity from unknown IP addresses on multiple accounts.",
         "Investigated access logs and confirmed unauthorized access attempts. Forced password reset for affected accounts, enabled geo-based login restrictions, and provided detailed incident report."),
        ("Vulnerability scan showing outdated TLS version on the customer's dedicated endpoint.",
         "Upgraded the TLS configuration from 1.1 to 1.3 on the customer's dedicated endpoint. Ran compliance scan to verify all cipher suites meet current security standards."),
        ("API keys exposed in a public repository triggering a security alert.",
         "Immediately revoked the compromised API keys and issued new ones. Audited access logs during the exposure window and found no unauthorized usage. Recommended implementing key rotation policies."),
        ("Customer requesting SOC 2 compliance documentation for their annual audit.",
         "Provided the current SOC 2 Type II report and compliance attestation. Scheduled a call with our security team to address specific audit questions and control mappings."),
    ],
}

CUSTOMER_IDS = [f"CUST-{i:04d}" for i in range(1, 51)]


def generate_support_cases(n=200):
    rows = []
    start_date = datetime(2025, 12, 1)
    for i in range(1, n + 1):
        case_id = f"CASE-{i:05d}"
        customer_id = random.choice(CUSTOMER_IDS)
        case_date = start_date + timedelta(days=random.randint(0, 89))
        product = random.choice(PRODUCTS)
        category = random.choice(ISSUE_CATEGORIES)
        priority = random.choices(PRIORITIES, weights=[20, 40, 30, 10])[0]
        status = random.choice(STATUSES)
        agent = random.choice(AGENT_NAMES)
        issue, resolution = random.choice(ISSUE_TEMPLATES[category])
        rows.append({
            "CASE_ID": case_id,
            "CUSTOMER_ID": customer_id,
            "CASE_DATE": case_date.strftime("%Y-%m-%d"),
            "PRODUCT": product,
            "ISSUE_CATEGORY": category,
            "ISSUE_SUMMARY": issue,
            "RESOLUTION_SUMMARY": resolution,
            "AGENT_NAME": agent,
            "STATUS": status,
            "PRIORITY": priority,
        })
    return rows


def generate_case_metrics(cases):
    rows = []
    for c in cases:
        priority_mult = {"Low": 1.0, "Medium": 1.2, "High": 1.5, "Critical": 2.0}[c["PRIORITY"]]
        first_response = max(1, int(random.gauss(15 * priority_mult, 5)))
        resolution_hours = max(0.5, round(random.gauss(8 * priority_mult, 3), 1))
        interactions = max(1, int(random.gauss(3 * priority_mult, 1.5)))
        csat = min(5.0, max(1.0, round(random.gauss(4.0 - (priority_mult - 1) * 0.5, 0.8), 1)))
        escalated = 1 if c["PRIORITY"] in ("High", "Critical") and random.random() < 0.3 else 0
        rows.append({
            "CASE_ID": c["CASE_ID"],
            "CUSTOMER_ID": c["CUSTOMER_ID"],
            "CASE_DATE": c["CASE_DATE"],
            "PRODUCT": c["PRODUCT"],
            "ISSUE_CATEGORY": c["ISSUE_CATEGORY"],
            "PRIORITY": c["PRIORITY"],
            "FIRST_RESPONSE_TIME_MINS": first_response,
            "RESOLUTION_TIME_HOURS": resolution_hours,
            "NUM_INTERACTIONS": interactions,
            "CSAT_SCORE": csat,
            "ESCALATED": escalated,
        })
    return rows


def generate_daily_metrics(cases):
    start = datetime(2025, 12, 1)
    date_map = {}
    for c in cases:
        d = c["CASE_DATE"]
        if d not in date_map:
            date_map[d] = []
        date_map[d].append(c)

    rows = []
    for day_offset in range(90):
        dt = start + timedelta(days=day_offset)
        ds = dt.strftime("%Y-%m-%d")
        total = random.randint(5, 20)
        resolved = int(total * random.uniform(0.6, 0.95))
        escalated = max(0, int(total * random.uniform(0.05, 0.2)))
        avg_res = round(random.gauss(10, 3), 1)
        avg_csat = round(random.gauss(3.8, 0.4), 1)
        avg_frt = round(random.gauss(18, 5), 1)
        rows.append({
            "METRIC_DATE": ds,
            "TOTAL_CASES": total,
            "CASES_RESOLVED": resolved,
            "CASES_ESCALATED": escalated,
            "AVG_RESOLUTION_TIME_HOURS": max(1.0, avg_res),
            "AVG_CSAT_SCORE": min(5.0, max(1.0, avg_csat)),
            "AVG_FIRST_RESPONSE_MINS": max(1.0, avg_frt),
        })
    return rows


def generate_agent_performance(cases):
    start = datetime(2025, 12, 1)
    rows = []
    for agent in AGENT_NAMES:
        for week in range(12):
            week_start = start + timedelta(weeks=week)
            handled = random.randint(8, 25)
            resolved = int(handled * random.uniform(0.7, 0.98))
            avg_res = round(random.gauss(9, 2.5), 1)
            avg_csat = round(random.gauss(3.9, 0.5), 1)
            esc_rate = round(random.uniform(0.02, 0.25), 2)
            rows.append({
                "AGENT_NAME": agent,
                "WEEK_START": week_start.strftime("%Y-%m-%d"),
                "CASES_HANDLED": handled,
                "CASES_RESOLVED": resolved,
                "AVG_RESOLUTION_TIME_HOURS": max(1.0, avg_res),
                "AVG_CSAT_SCORE": min(5.0, max(1.0, avg_csat)),
                "ESCALATION_RATE": esc_rate,
            })
    return rows


def write_csv(filename, rows):
    path = os.path.join(OUTPUT_DIR, filename)
    with open(path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)
    print(f"Wrote {len(rows)} rows to {path}")


if __name__ == "__main__":
    cases = generate_support_cases(200)
    write_csv("support_cases.csv", cases)

    metrics = generate_case_metrics(cases)
    write_csv("case_metrics.csv", metrics)

    daily = generate_daily_metrics(cases)
    write_csv("daily_support_metrics.csv", daily)

    agent_perf = generate_agent_performance(cases)
    write_csv("agent_performance.csv", agent_perf)

    print("Data generation complete.")
