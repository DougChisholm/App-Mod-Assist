use the SQL database you created earlier:

Server=tcp:<example>.database.windows.net,1433;Initial Catalog=<ExampleDB>;Encrypt=True;
TrustServerCertificate=False;Connection Timeout=30;

connect using the managedidentiy you created before using this format:

string connectionString = "Server=tcp:<server>.database.windows.net;" +
                          "Database=<db>;" +
                          "Authentication=Active Directory Managed Identity;" +
                          "User Id=<client-id-of-user-assigned-mi>;";

do not create any other kind of db access like user name password or tokens just managed identity to avoid this potential issue:

"The connection is failing because your code is trying to use access token authentication (setting connection.AccessToken), 
but you also have Authentication=Active Directory Managed Identity in the connection string - 
these two approaches conflict with each other."

Also add instruction to run the app locally by changing the connection string in appsettings to use "Authentication=Active Directory Default" which will ask local user to login with az login
