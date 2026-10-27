FROM liquibase/liquibase:4.33.0
COPY --chown=liquibase:liquibase changelog /liquibase/changelog/changelog
COPY --chown=liquibase:liquibase db /liquibase/changelog/db
WORKDIR /liquibase/changelog
ENV LIQUIBASE_COMMAND_CHANGELOG_FILE=changelog/primary.xml
CMD ["update"]
