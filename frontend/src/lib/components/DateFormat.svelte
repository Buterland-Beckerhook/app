<script lang="ts">
	let { date, withTime = false }: { date: string; withTime?: boolean } = $props();

	let formatted = $derived(
		new Date(date).toLocaleDateString('de-DE', {
			day: '2-digit',
			month: '2-digit',
			year: 'numeric'
		})
	);

	let timeFormatted = $derived(
		withTime
			? new Date(date).toLocaleTimeString('de-DE', {
					hour: '2-digit',
					minute: '2-digit'
				})
			: null
	);
</script>

<span
	>{formatted}{#if timeFormatted}, {timeFormatted} Uhr{/if}</span
>
