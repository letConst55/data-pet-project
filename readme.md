- Чтобы все включить 

`./start_pipeline.sh`

- Чтобы выключить

`./stop_pipeline.sh`

Креды для MiniO админки (http://localhost:9001/)

 - логин: minioadmin
 - пароль: miniopassword

Airflow http://localhost:8080/

 - логин: admin
 - пароль: YuxUPBsY9FGeSSPd

Grafana http://localhost:3000/

 - логин: admin
 - пароль: 1234


Полностью пересчитать все dbt модели и тесты проекта (находясь в папке analytics)

`dbt build --full-refresh`