use sqlx::postgres::PgPoolOptions;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let pool = PgPoolOptions::new()
        .connect(&std::env::var("DATABASE_URL")?)
        .await?;

    let rows = sqlx::query!(
        r#"SELECT p.id, u.display_name AS author_display_name
           FROM posts_min p
           LEFT JOIN users_min u ON u.id = p.author_id"#
    )
    .fetch_all(&pool)
    .await?;

    for row in rows {
        println!("{:?} {:?}", row.id, row.author_display_name);
    }

    Ok(())
}
