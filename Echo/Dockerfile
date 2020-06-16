FROM mcr.microsoft.com/dotnet/core/aspnet:3.1 AS base
WORKDIR /app
EXPOSE 80

FROM mcr.microsoft.com/dotnet/core/sdk:3.1 AS build
WORKDIR /src
COPY ["Echo/Echo.csproj", "Echo/"]
RUN dotnet restore "Echo/Echo.csproj"
COPY . .
WORKDIR "/src/Echo"
RUN dotnet build "Echo.csproj" -c Release -o /app/build

FROM build AS publish
RUN dotnet publish "Echo.csproj" -c Release -o /app/publish

FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .
ENTRYPOINT ["dotnet", "Echo.dll"]
