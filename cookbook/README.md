GitHub Notification Proxy Cookbook
==================================

Installs and configures the GitHub Notification Proxy via Chef.

The server recipe performs the following actions:

1. Creates a `github` user
2. Installs PostgreSQL and creates a database
3. Installs RVM, installs ruby, and configures a `github-notification-proxy` gemset
4. Clones the `github-notification-proxy` repository from GitHub
5. Creates an upstart job to run the server process

The client recipe performs the following actions:

1. Creates a `github` user
2. Installs RVM, installs ruby, and configures a `github-notification-proxy` gemset
3. Clones the `github-notification-proxy` repository from GitHub
4. Creates an upstart job to run the client process
