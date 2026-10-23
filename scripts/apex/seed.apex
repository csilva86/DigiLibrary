List<Account> accs = new List<Account>();
String[] industries = new String[]{'Technology','Finance','Retail','Healthcare','Energy'};
String[] ufs = new String[]{'SP','RJ','MG','RS','PR'};

//* Create Accounts
for (Integer i = 0; i < 200; i++) {
    accs.add(new Account(
        Name = 'Conta ' + String.valueOf(i).leftPad(3, '0'),
        Industry = industries[Math.mod(i, 5)],
        BillingCountryCode = 'BR',
        BillingStateCode = ufs[Math.mod(i, 5)],
        AnnualRevenue = (i + 1) * 100000,
        NumberOfEmployees = (i + 1) * 10));
}
insert accs;

String[] stages = new String[]{'Prospecting','Qualification','Negotiation/Review','Closed Won','Closed Lost'};
List<Contact> cons = new List<Contact>();
List<Opportunity> opps = new List<Opportunity>();
List<Task> tasks = new List<Task>();
for (Integer i = 0; i < accs.size(); i++) {
    Account a = accs[i];

    //* Create Contacts
    for (Integer j = 0; j < Math.mod(i, 4); j++) {
        cons.add(new Contact(LastName = 'Contato ' + i + '-' + j,
            Email = 'c' + i + '_' + j + '@exemplo.com', AccountId = a.Id));
    }

    //* Create Opportunities
    for (Integer k = 0; k < Math.mod(i, 3) + 1; k++) {
        opps.add(new Opportunity(Name = a.Name + ' Opp ' + k, AccountId = a.Id,
            StageName = stages[Math.mod(i + k, 5)],
            CloseDate = Date.today().addDays(Math.mod(i * 7 + k, 180) - 90),
            Amount = (Math.mod(i, 10) + 1) * 5000 * (k + 1)));
    }

    //* Create Tasks
    if (Math.mod(i, 10) == 0) {
        tasks.add(new Task(Subject = 'Follow-up ' + a.Name, WhatId = a.Id));
    }
}
insert cons;
insert opps;
insert tasks;