# Use a lightweight web server to serve the static files
FROM nginx:alpine

# Copy the build files from the local machine into the container
COPY . /usr/share/nginx/html

# Expose port 80 to the outside world
EXPOSE 80

# Start Nginx server
CMD ["nginx", "-g", "daemon off;"]