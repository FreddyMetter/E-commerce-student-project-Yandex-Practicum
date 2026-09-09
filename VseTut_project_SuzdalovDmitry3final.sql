/* Проект «Разработка витрины и решение ad-hoc задач»
 * Цель проекта: подготовка витрины данных маркетплейса «ВсёТут»
 * и решение четырех ad hoc задач на её основе
 * 
 * Автор: Суздалов Дмитрий Freddy.metter
 * Дата: 07.09.2026
*/



/* Часть 1. Разработка витрины данных
 * Напишите ниже запрос для создания витрины данных
*/

WITH top_3_region AS (
	SELECT
		u.region,
		COUNT(o.order_id) AS total_orders
	FROM ds_ecom.users AS u
	LEFT JOIN ds_ecom.orders AS o USING(buyer_id)
	WHERE o.order_status IN ('Доставлено', 'Отменено')
	GROUP BY u.region 
	ORDER BY total_orders DESC
	LIMIT 3
),
valid_orders AS (
	SELECT DISTINCT
		u.region,
		o.order_id,
		o.buyer_id,
		o.order_purchase_ts,
		o.order_status
	FROM ds_ecom.users AS u
	LEFT JOIN ds_ecom.orders AS o USING(buyer_id)
	INNER JOIN ds_ecom.order_items AS oi USING(order_id)
	WHERE u.region IN (SELECT region FROM top_3_region) AND o.order_status IN ('Доставлено', 'Отменено')
),
user_info AS (
SELECT
	u.user_id,
	u.region,
	MIN(vo.order_purchase_ts) AS first_order_ts,
	MAX(vo.order_purchase_ts) AS last_order_ts,
	MAX(vo.order_purchase_ts)::timestamp - MIN(vo.order_purchase_ts)::timestamp AS lifetime
FROM ds_ecom.users AS u
LEFT JOIN valid_orders AS vo USING(buyer_id)
WHERE u.region IN (SELECT region FROM top_3_region) AND vo.order_status IN ('Доставлено', 'Отменено')
GROUP BY u.user_id, u.region
),
order_rating AS (
	SELECT 
		ov.order_id,
		AVG(CASE WHEN ov.review_score >= 10 THEN ov.review_score / 10 ELSE ov.review_score END) AS avg_order_rating_order
	FROM ds_ecom.order_reviews AS ov
	GROUP BY ov.order_id
),
user_orders AS (
	SELECT
		u.user_id,
		u.region,
		COUNT(vo.order_id) AS total_orders,
		AVG(ort.avg_order_rating_order) AS avg_order_rating,
		COUNT(ort.order_id) AS num_orders_with_rating,
		COUNT(vo.order_id) FILTER (WHERE vo.order_status = 'Отменено') AS num_canceled_orders,
		((COUNT(vo.order_id) FILTER (WHERE vo.order_status = 'Отменено'))::numeric / COUNT(vo.order_id)) AS canceled_orders_ratio
	FROM ds_ecom.users AS u 
	LEFT JOIN valid_orders AS vo USING(buyer_id)
	LEFT JOIN order_rating AS ort USING(order_id)
	WHERE u.region IN (SELECT region FROM top_3_region) AND vo.order_status IN ('Доставлено', 'Отменено')
	GROUP BY u.user_id, u.region
),
orders_costs AS (
	SELECT
		oi.order_id,
		SUM(oi.price + oi.delivery_cost) AS order_cost
	FROM ds_ecom.order_items AS oi
	GROUP BY oi.order_id
),
orders_features AS (
	SELECT
		op.order_id,
		MAX(CASE
				WHEN op.payment_installments > 1
					THEN 1
					ELSE 0
		END) AS with_installments,
		MAX(CASE
				WHEN op.payment_type = 'промокод'
					THEN 1
					ELSE 0
		END) AS with_promo
	FROM ds_ecom.order_payments AS op
	GROUP BY op.order_id
),
user_payments AS (
	SELECT
		u.user_id,
		u.region,
		SUM(CASE WHEN vo.order_status = 'Отменено' THEN NULL ELSE oc.order_cost END) AS total_order_costs,
		AVG(CASE WHEN vo.order_status = 'Отменено' THEN NULL ELSE oc.order_cost END) AS avg_order_cost,
		COUNT(oc.order_id) FILTER (WHERE ofe.with_installments = 1) AS num_installment_orders,
		COUNT(oc.order_id) FILTER (WHERE ofe.with_promo = 1) AS num_orders_with_promo  
	FROM ds_ecom.users AS u
	LEFT JOIN valid_orders AS vo USING(buyer_id)
	LEFT JOIN orders_costs AS oc USING(order_id)
	LEFT JOIN orders_features AS ofe USING(order_id)
	WHERE u.region IN (SELECT region FROM top_3_region)
	GROUP BY u.user_id, u.region
),
first_payment AS (
	SELECT 
		order_id,
		(ARRAY_AGG(payment_type ORDER BY payment_sequential))[1] AS first_payment_type,
		MAX(CASE WHEN payment_installments > 1 THEN 1 ELSE 0 END) AS with_installment_pay
	FROM ds_ecom.order_payments op GROUP BY order_id
),
binary_features AS (
	SELECT
		u.user_id,
		u.region,
		MAX(CASE 
			WHEN fp.first_payment_type = 'денежный перевод'
				THEN 1
				ELSE 0
		END) AS used_money_transfer,
		MAX(fp.with_installment_pay) AS used_installments,
		MAX(CASE 
			WHEN vo.order_status = 'Отменено'
				THEN 1
				ELSE 0
		END) AS used_cancel
	FROM ds_ecom.users AS u
	INNER JOIN valid_orders AS vo USING(buyer_id)
	LEFT JOIN first_payment AS fp USING(order_id)
	WHERE u.region IN (SELECT region FROM top_3_region)
	GROUP BY u.user_id, u.region
)
SELECT 
	ui.user_id,
	ui.region,
	ui.first_order_ts,
	ui.last_order_ts,
	ui.lifetime,
	uo.total_orders,
	uo.avg_order_rating,
	uo.num_orders_with_rating,
	uo.num_canceled_orders,
	uo.canceled_orders_ratio,
	up.total_order_costs,
	up.avg_order_cost,
	up.num_installment_orders,
	up.num_orders_with_promo,
	bf.used_money_transfer,
	bf.used_installments,
	bf.used_cancel
FROM user_info AS ui
LEFT JOIN user_orders AS uo ON ui.user_id = uo.user_id AND ui.region = uo.region
LEFT JOIN user_payments AS up ON ui.user_id = up.user_id AND ui.region = up.region
LEFT JOIN binary_features AS bf ON ui.user_id = bf.user_id AND ui.region = bf.region
ORDER BY total_orders DESC;


/* Часть 2. Решение ad hoc задач
 * Для каждой задачи напишите отдельный запрос.
 * После каждой задачи оставьте краткий комментарий с выводами по полученным результатам.
*/

/* Задача 1. Сегментация пользователей 
 * Разделите пользователей на группы по количеству совершённых ими заказов.
 * Подсчитайте для каждой группы общее количество пользователей,
 * среднее количество заказов, среднюю стоимость заказа.
 * 
 * Выделите такие сегменты:
 * - 1 заказ — сегмент 1 заказ
 * - от 2 до 5 заказов — сегмент 2-5 заказов
 * - от 6 до 10 заказов — сегмент 6-10 заказов
 * - 11 и более заказов — сегмент 11 и более заказов
*/

-- Напишите ваш запрос тут

SELECT 
	CASE 
		WHEN total_orders = 1 THEN '1 заказ'
		WHEN total_orders > 1 AND total_orders <= 5 THEN '2-5 заказов'
		WHEN total_orders > 5 AND total_orders <= 10 THEN '6-10 заказов'
		ELSE '11 и более заказов'
	END AS user_segmentation,
	COUNT(user_id) AS amount_of_users,
	AVG(total_orders) AS avg_orders,
	SUM(total_order_costs) / SUM(total_orders) AS avg_cost
FROM ds_ecom.product_user_features
GROUP BY user_segmentation 
ORDER BY amount_of_users DESC;

/* Напишите краткий комментарий с выводами по результатам задачи 1.
 * 
 * Подавляющее большинство пользователей заказывают лишь 1 товар за все время, 
 * при этом средний чек у них самый высокий среди всех групп. 
 * Существует обратная корреляция: чем больше человек заказывает, тем ниже его средний чек.
 * 
*/



/* Задача 2. Ранжирование пользователей 
 * Отсортируйте пользователей, сделавших 3 заказа и более, по убыванию среднего чека покупки.  
 * Выведите 15 пользователей с самым большим средним чеком среди указанной группы.
*/

-- Напишите ваш запрос тут

SELECT 
	RANK() OVER(ORDER BY avg_order_cost DESC),
	*
FROM ds_ecom.product_user_features
WHERE total_orders >= 3
ORDER BY avg_order_cost DESC
LIMIT 15

/* Напишите краткий комментарий с выводами по результатам задачи 2.
 * 
 * Самый большой средний чек у среза "3 заказа и более" у людей с тремя заказами. 
 * Они пользуются рассрочной и почти все их заказы взяты с ее помощью.
 * 
*/



/* Задача 3. Статистика по регионам. 
 * Для каждого региона подсчитайте:
 * - общее число клиентов и заказов;
 * - среднюю стоимость одного заказа;
 * - долю заказов, которые были куплены в рассрочку;
 * - долю заказов, которые были куплены с использованием промокодов;
 * - долю пользователей, совершивших отмену заказа хотя бы один раз.
*/

-- Напишите ваш запрос тут

SELECT
	region,
	COUNT(user_id) AS total_users_region,
	SUM(total_orders) AS total_orders_region,
	SUM(total_order_costs) * 1.0 / SUM(total_orders) AS avg_cost_order,
	(COUNT(total_orders) FILTER (WHERE used_installments = 1)) / SUM(total_orders) AS share_of_installment,
	(COUNT(total_orders) FILTER (WHERE num_orders_with_promo = 1)) / SUM(total_orders) AS share_of_promo,
	(COUNT(total_orders) FILTER (WHERE used_cancel = 1)) / SUM(total_orders) AS share_of_cancel_users
FROM ds_ecom.product_user_features
GROUP BY region
ORDER BY total_users_region DESC;

/* Напишите краткий комментарий с выводами по результатам задачи 3.
 * 
 * Ожидаемо самый активный регион с кратным отрывом - Москва
 * 
*/



/* Задача 4. Активность пользователей по первому месяцу заказа в 2023 году
 * Разбейте пользователей на группы в зависимости от того, в какой месяц 2023 года они совершили первый заказ.
 * Для каждой группы посчитайте:
 * - общее количество клиентов, число заказов и среднюю стоимость одного заказа;
 * - средний рейтинг заказа;
 * - долю пользователей, использующих денежные переводы при оплате;
 * - среднюю продолжительность активности пользователя.
*/

-- Напишите ваш запрос тут

SELECT 
	DATE_TRUNC('month', first_order_ts) AS month_2023,
	COUNT(user_id) AS total_users_month,
	SUM(total_orders) AS total_orders_month,
	SUM(total_order_costs) * 1.0 / SUM(total_orders) AS total_order_costs_month, --
	AVG(avg_order_rating) AS avg_rating_month,
	(COUNT(user_id) FILTER (WHERE used_money_transfer = 1)) / COUNT(user_id)::numeric AS share_of_transfer,
	AVG(lifetime) AS avg_lifetime_month
FROM ds_ecom.product_user_features
WHERE EXTRACT(YEAR FROM first_order_ts) = 2023
GROUP BY month_2023
ORDER BY month_2023;

/* Напишите краткий комментарий с выводами по результатам задачи 4.
 * 
 * Количество пользователей и заказов синхронно и пропорционально растет по мере года достигая апогея в ноябре-декабре. 
 * Остальные метрики держатся примерно на одном уровне, за исключением жизненного цикла, который постепенно уменьшается к концу года
 * 
*/