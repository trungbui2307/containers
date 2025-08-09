#!/bin/bash

set -e 

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
ACTIOn="up"
SERVICES=()
SCALE_WORKERS=""
DETACHED=true

show_help() {
	echo -e "${BLUE}Service Manager for Docker Compose Services${NC}"
	echo ""
	echo "Usage: $0 [OPTIONS] [ACTION]"
	echo ""
	echo -e "${YELLOW}Services:${NC}"
	echo " --traefik		Manage Traefik reverse proxy"
	echo " --postgres 		Manage PostgreSQL database"
	echo " --n8n			Manage n8n workflow automation"
	echo " --dbeaver 		Manage DBeaver (included with PostgreSQL)"
        echo " --all 			Manage all services"
	echo ""
	echo -e "${YELLOW}Actions:${NC}"
	echo " up			Start services (default)"
	echo " down			Stop and remove services"
	echo " restart 			Restart services"
	echo " stop			Stop services"
	echo " start			Start existing services"
	echo " logs 			Show logs"
	echo " status 			Show service status"
	echo " pull 			Pull latest images"
	echo ""
	echo -e "${YELLOW}Options:${NC}"
	echo " --help			Show this help message"
	echo " --foreground  		Run in foreground (don't detach)"
	echo ""
	echo -e "${YELLOW}Examples:${NC}"
        echo " $0 --traefik up 		# Start Traefik"
        echo " $0 --postgres --n8n up  	# Start PostgreSQL and n8n"
        echo " $0 --all down            # Stop all services"
    	echo " $0 --n8n logs            # Show n8n logs"
    	echo " $0 --all status          # Show status of all services"
}

# Function to log messages
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if directory exists
check_directory() {
    local dir=$1
    if [ ! -d "$dir" ]; then
        log_error "Directory $dir does not exist!"
        return 1
    fi
    return 0
}

run_compose() {
    local service=$1
    local action=$2
    local extra_args=$3

    if ! check_directory "$service"; then
        return 1
    fi

    log "Running $action for $service..."
    cd "$service" || exit 1

    case $action in
        "up")
            if [ "$DETACHED" = true ]; then
                docker-compose up -d $extra_args
            else
                docker-compose up $extra_args
            fi
            ;;
        "down")
            docker-compose down $extra_args
            ;;
        "restart")
            docker-compose restart $extra_args
            ;;
        "stop")
            docker-compose stop $extra_args
            ;;
        "start")
            docker-compose start $extra_args
            ;;
        "logs")
            docker-compose logs -f $extra_args
            ;;
        "status")
            docker-compose ps $extra_args
            ;;
        "pull")
            docker-compose pull $extra_args
            ;;
        *)
            log_error "Unknown action: $action"
            return 1
            ;;
    esac

    cd - > /dev/null || exit 1
}

# Function to manage services
manage_services() {
    local action=$1

    # Create networks if they don't exist (for up action)
    if [ "$action" = "up" ]; then
        log "Creating Docker networks if they don't exist..."
        docker network create traefik 2>/dev/null || true
        docker network create postgres-network 2>/dev/null || true
    fi

    # Process services in the correct order
    for service in "${SERVICES[@]}"; do
        case $service in
            "traefik")
                run_compose "traefik" "$action"
                ;;
            "postgres")
                run_compose "postgres" "$action"
                ;;
            "n8n")
                run_compose "n8n" "$action"
                ;;
            "dbeaver")
                run_compose "postgres" "$action"  # DBeaver is now part of postgres
                ;;
        esac

        # Add a small delay between services for startup
        if [ "$action" = "up" ] && [ ${#SERVICES[@]} -gt 1 ]; then
            sleep 2
        fi
    done
}

# Function to show status of all services
show_all_status() {
    echo -e "${BLUE}=== Service Status ===${NC}"
    echo ""
    
    # Check Traefik
    if check_directory "traefik" 2>/dev/null; then
        echo -e "${YELLOW}Traefik:${NC}"
        cd traefik && docker-compose ps && cd - > /dev/null
        echo ""
    fi
    
    # Check PostgreSQL
    if check_directory "postgres" 2>/dev/null; then
        echo -e "${YELLOW}PostgreSQL:${NC}"
        cd postgres && docker-compose ps && cd - > /dev/null
        echo ""
    fi
    
    # Check n8n
    if check_directory "n8n" 2>/dev/null; then
        echo -e "${YELLOW}n8n:${NC}"
        cd n8n && docker-compose ps && cd - > /dev/null
        echo ""
    fi
}

# Function to show logs from all services
show_all_logs() {
    echo -e "${BLUE}=== Service Logs ===${NC}"
    echo "Press Ctrl+C to stop following logs"
    echo ""

    # Create a temporary file for log aggregation
    temp_file=$(mktemp)

    # Function to cleanup on exit
    cleanup() {
        rm -f "$temp_file"
        pkill -P $$ 2>/dev/null || true
    }
    trap cleanup EXIT

    # Start log collection in background
    for service in "${SERVICES[@]}"; do
        if check_directory "$service" 2>/dev/null; then
            (cd "$service" && docker-compose logs -f --tail=50 2>/dev/null | sed "s/^/[$service] /") &
        fi
    done

    # Wait for user interrupt
    wait
}


while [[ $# -gt 0 ]]; do
    case $1 in
        --traefik)
            SERVICES+=("traefik")
            shift
            ;;
        --postgres)
            SERVICES+=("postgres")
            shift
            ;;
        --n8n)
            SERVICES+=("n8n")
            shift
            ;;
        --dbeaver)
            SERVICES+=("postgres")  # DBeaver is now part of postgres compose
            shift
            ;;
        --all)
            SERVICES=("traefik" "postgres" "n8n")
            shift
            ;;
        --scale)
            SCALE_WORKERS="$2"
            if ! [[ "$SCALE_WORKERS" =~ ^[0-9]+$ ]]; then
                log_error "Scale value must be a number"
                exit 1
            fi
            shift 2
            ;;
        --foreground)
            DETACHED=false
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        up|down|restart|stop|start|logs|status|pull)
            ACTION="$1"
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Check if any services were specified
if [ ${#SERVICES[@]} -eq 0 ]; then
    log_error "No services specified!"
    echo ""
    show_help
    exit 1
fi

# Handle special cases
case $ACTION in
    "status")
        if [[ " ${SERVICES[*]} " =~ " traefik " ]] && [[ " ${SERVICES[*]} " =~ " postgres " ]] && [[ " ${SERVICES[*]} " =~ " n8n " ]]; then
            show_all_status
        else
            manage_services "$ACTION"
        fi
        ;;
    "logs")
        if [ ${#SERVICES[@]} -gt 1 ]; then
            show_all_logs
        else
            manage_services "$ACTION"
        fi
        ;;
    *)
        manage_services "$ACTION"
        ;;
esac

log "Operation completed successfully!"
