#!/bin/bash
# DNS Sync Health Check Script
# Monitors the health of DNS GitOps synchronization

LOGFILE="/var/log/gitops-sync.log"
LAST_SUCCESS_FILE="/var/run/gitops-dns-last-success"
MAX_AGE_MINUTES=15  # Alert if no successful sync in 15 minutes

echo "==================================="
echo "DNS GitOps Sync Health Check"
echo "==================================="
echo ""

# Check if service is enabled
TIMER_STATUS=$(systemctl is-active gitops-sync.timer 2>/dev/null)
if [ "$TIMER_STATUS" != "active" ]; then
    echo "❌ CRITICAL: gitops-sync.timer is not active"
    exit 2
fi
echo "✓ Timer Status: Active"

# Check last successful sync
if [ -f "$LOGFILE" ]; then
    LAST_SUCCESS=$(grep "DNS sync completed successfully" "$LOGFILE" | tail -1)
    if [ -n "$LAST_SUCCESS" ]; then
        echo "✓ Last Successful Sync:"
        echo "  $LAST_SUCCESS"
        
        # Extract timestamp and calculate age
        TIMESTAMP=$(echo "$LAST_SUCCESS" | grep -oP '\[\K[0-9-]+ [0-9:]+')
        if [ -n "$TIMESTAMP" ]; then
            LAST_SYNC_EPOCH=$(date -d "$TIMESTAMP" +%s 2>/dev/null)
            CURRENT_EPOCH=$(date +%s)
            AGE_MINUTES=$(( ($CURRENT_EPOCH - $LAST_SYNC_EPOCH) / 60 ))
            
            echo "  Age: $AGE_MINUTES minutes ago"
            
            if [ $AGE_MINUTES -gt $MAX_AGE_MINUTES ]; then
                echo "⚠️  WARNING: Last successful sync was over $MAX_AGE_MINUTES minutes ago"
            fi
        fi
    else
        echo "⚠️  WARNING: No successful sync found in logs"
    fi
else
    echo "❌ ERROR: Log file not found: $LOGFILE"
    exit 1
fi

echo ""

# Check for recent errors
RECENT_ERRORS=$(grep -c "ERROR.*DNS" "$LOGFILE" | tail -20 || echo "0")
if [ "$RECENT_ERRORS" -gt "0" ]; then
    echo "⚠️  Recent Errors: $RECENT_ERRORS"
    echo "  Last 3 errors:"
    grep "ERROR.*DNS" "$LOGFILE" | tail -3 | sed 's/^/    /'
else
    echo "✓ No recent DNS sync errors"
fi

echo ""

# Check validation warnings
RECENT_WARNINGS=$(grep "ABORTING\|conversion errors" "$LOGFILE" | tail -5)
if [ -n "$RECENT_WARNINGS" ]; then
    echo "⚠️  Critical Validation Issues:"
    echo "$RECENT_WARNINGS" | sed 's/^/    /'
    echo ""
fi

# Check zone file count
ZONE_COUNT=$(find /opt/gitops/iac-catalog/environments/global/configurations/dns-zones -name "*.zone" -type f 2>/dev/null | wc -l)
echo "✓ Active Zones: $ZONE_COUNT"

# Check last sync statistics
LAST_STATS=$(grep "Zone files processed\|DNS records parsed\|Hosts entries generated" "$LOGFILE" | tail -3)
if [ -n "$LAST_STATS" ]; then
    echo ""
    echo "Last Sync Statistics:"
    echo "$LAST_STATS" | sed 's/^/  /'
fi

echo ""
echo "==================================="

# Exit code: 0 = healthy, 1 = warnings, 2 = critical
if [ "$TIMER_STATUS" != "active" ]; then
    exit 2
elif [ "$RECENT_ERRORS" -gt "5" ]; then
    exit 1
else
    exit 0
fi
