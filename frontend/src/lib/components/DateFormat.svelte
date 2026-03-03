<script lang="ts">
    let {date, withDate = true, withTime = false, timeSeparator = ','}: {
        date: string;
        withDate?: boolean;
        withTime?: boolean;
        timeSeparator?: string
    } = $props();


    let dateFormatted = $derived(
        withDate
        ? new Date(date).toLocaleDateString('de-DE', {
            day: '2-digit',
            month: 'long',
            year: 'numeric'
        }) : ''
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
>{dateFormatted}
    {#if timeFormatted}{timeSeparator} {timeFormatted} Uhr{/if}</span
>
