import { LightningElement } from 'lwc';
export default class Activity extends LightningElement {

activities = [
{
id: 1,
type: 'email',
subject: 'Send Letter',
description: 'You sent an email',
date: 'Jun 11'
},
{
id: 2,
type: 'call',
subject: 'Call',
description: 'You sent an email',
date: 'May 31'
}
];

isUpcomingOpen = true;

toggleUpcoming() {
this.isUpcomingOpen = !this.isUpcomingOpen;
}

get upcomingIcon() {
return this.isUpcomingOpen
? 'utility:chevrondown'
: 'utility:chevronright';
}

}